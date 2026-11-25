import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../ai/image_split.dart';
import '../../app_state.dart';
import '../../domain/batch.dart';
import '../../domain/expiry_date_parser.dart';
import '../../domain/gs1_parser.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../../services/ocr_service.dart';

/// The steps that read a photo. Real ones use ML Kit, the product databases
/// and the user's AI; tests swap them for fakes.
class BatchProcessors {
  const BatchProcessors({
    required this.scanBarcode,
    required this.lookup,
    required this.ocr,
    required this.aiProduct,
    required this.aiDate,
    required this.aiReceipt,
  });

  final Future<String?> Function(String path) scanBarcode;
  final Future<ProductInfo?> Function(String ean) lookup;
  final Future<String> Function(String path) ocr;

  /// null = no AI available or nothing recognised.
  final Future<({String name, String? brand, String categoryId})?> Function(Uint8List photo) aiProduct;
  final Future<({DateTime date, DateType? type})?> Function(Uint8List photo) aiDate;
  final Future<List<ReceiptLine>> Function(Uint8List photo) aiReceipt;
}

final batchProcessorsProvider = Provider<BatchProcessors>((ref) {
  Future<T?> ai<T extends Object>(AiFeature f, AiRequest r, T? Function(String) parse) async {
    final s = ref.read(aiServiceProvider);
    if (!s.enabledFor(f)) return null;
    try {
      return await s.runParsed<T?>(f, r, parse);
    } catch (_) {
      return null;
    }
  }

  return BatchProcessors(
    scanBarcode: (path) async {
      if (kIsWeb) return null;
      final controller = MobileScannerController(autoStart: false);
      try {
        final r = await controller.analyzeImage(path);
        return r?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
      } catch (_) {
        return null;
      } finally {
        await controller.dispose();
      }
    },
    lookup: (ean) async {
      final h = ref.read(activeHouseholdProvider);
      if (h == null) return null;
      try {
        return await ref.read(productLookupProvider).lookup(h.id, ean);
      } catch (_) {
        return null;
      }
    },
    ocr: (path) => OcrService.recognize(XFile(path)),
    aiProduct: (bytes) => ai(AiFeature.product, productRequest(AiImage.detect(bytes), _lang(ref)), parseProduct),
    aiDate: (bytes) => ai(AiFeature.date, dateRequest(AiImage.detect(bytes), DateTime.now()), parseDate),
    aiReceipt: (bytes) async {
      final s = ref.read(aiServiceProvider);
      if (!s.enabledFor(AiFeature.receipt)) throw const AiException('no-provider');
      final parts = await compute(splitTallImage, AiImage.detect(bytes));
      return s.runParsed(AiFeature.receipt, receiptRequest(parts, _lang(ref)), (t) {
        final lines = parseReceipt(t);
        if (lines.isEmpty) throw const AiException('empty', transient: true);
        return lines;
      });
    },
  );
});

String _lang(Ref ref) => ref.read(settingsProvider).locale?.languageCode ?? PlatformDispatcher.instance.locale.languageCode;

enum ReceiptState { none, reading, done, failed }

/// A row of the review list: a photographed product (maybe paired with a
/// receipt line) or a receipt line nobody photographed.
class ReviewRow {
  ReviewRow({
    required this.key,
    required this.item,
    this.product,
    this.lineIndex,
    this.dateSource,
    this.busy = false,
  });

  final String key;
  final PantryItem item;
  final BatchProduct? product;
  final int? lineIndex;
  final DateSource? dateSource;
  final bool busy;

  bool get fromReceiptOnly => product == null;
  bool get onReceipt => lineIndex != null;
}

/// The whole series; lives outside the screens, so rotating the phone or
/// leaving the screen doesn't stop the processing.
class BatchJob extends Notifier<int> {
  @override
  int build() => 0;

  final products = <BatchProduct>[];
  List<BatchReceiptLine> receiptLines = const [];
  ReceiptState receiptState = ReceiptState.none;
  String? receiptError;
  bool pairingOn = true;

  /// Manual pairing: product id → line index (null = "not on the receipt").
  final manualPairs = <String, int?>{};

  /// Rows the user unticked / ticked (otherwise food is ticked).
  final selection = <String, bool>{};

  /// Rows the user edited.
  final edits = <String, PantryItem>{};

  /// The product whose date photo is expected next.
  String? awaitingDateFor;

  /// The next photo replaces this one (product id, date side or barcode side).
  ({String id, bool date})? retake;

  /// Receipt lines the user removed from the review.
  final hiddenLines = <int>{};

  Future<void> _queue = Future.value();
  int _seq = 0;

  bool get isEmpty => products.isEmpty && receiptLines.isEmpty;
  int get photoCount => products.fold(0, (n, p) => n + (p.barcodePath == null ? 0 : 1) + (p.datePath == null ? 0 : 1));
  int get processing => products.where((p) => p.busy).length;

  void _touch() => state = state + 1;

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((_) {}).whenComplete(_touch);
  }

  BatchProcessors get _proc => ref.read(batchProcessorsProvider);

  /// Step 1: the barcode side of a new product.
  void addBarcodePhoto(String path) {
    final p = BatchProduct(id: 'p${_seq++}', barcodePath: path);
    products.add(p);
    awaitingDateFor = p.id;
    _touch();
    _enqueue(() => _readProduct(p));
  }

  /// Step 2: the date of the product photographed last.
  void addDatePhoto(String path) {
    final p = products.where((x) => x.id == awaitingDateFor).firstOrNull;
    awaitingDateFor = null;
    if (p == null) return;
    p.datePath = path;
    _touch();
    _enqueue(() => _readDate(p));
  }

  /// The next shot replaces the barcode (or date) photo of [id].
  void setRetake(String id, {required bool date}) {
    retake = (id: id, date: date);
    _touch();
  }

  void cancelRetake() {
    retake = null;
    _touch();
  }

  /// A shot taken while [retake] is set: replace the photo and read it again.
  void replacePhoto(String path) {
    final r = retake;
    retake = null;
    final p = products.where((x) => x.id == r?.id).firstOrNull;
    if (r == null || p == null) return;
    edits.remove('p:${p.id}');
    if (r.date) {
      p
        ..datePath = path
        ..skipDate = false
        ..expiry = null
        ..dateType = null
        ..dateSource = null
        ..dateState = ShotState.processing;
      if (awaitingDateFor == p.id) awaitingDateFor = null;
      _touch();
      _enqueue(() => _readDate(p));
    } else {
      final keepDate = p.dateSource != DateSource.code;
      p
        ..barcodePath = path
        ..ean = null
        ..name = ''
        ..brand = null
        ..categoryId = 'other'
        ..nutrition = null
        ..locationType = null
        ..shelfLifeDays = null
        ..productSource = ProductSource.unknown
        ..productState = ShotState.processing;
      if (!keepDate) {
        p
          ..expiry = null
          ..dateSource = null
          ..dateState = p.datePath == null ? ShotState.done : ShotState.processing;
      }
      _touch();
      _enqueue(() async {
        await _readProduct(p);
        if (!keepDate && p.datePath != null) await _readDate(p);
      });
    }
  }

  /// Removes a review row (a product with its photos, or a receipt line);
  /// returns what puts it back.
  void Function() removeRow(ReviewRow row) {
    final p = row.product;
    if (p != null) {
      final at = products.indexOf(p);
      products.remove(p);
      if (awaitingDateFor == p.id) awaitingDateFor = null;
      _touch();
      return () {
        products.insert(at.clamp(0, products.length), p);
        _touch();
      };
    }
    final i = row.lineIndex!;
    hiddenLines.add(i);
    _touch();
    return () {
      hiddenLines.remove(i);
      _touch();
    };
  }

  /// Removes several rows at once; returns what puts them all back.
  void Function() removeRows(Iterable<ReviewRow> rows) {
    final undos = [for (final r in rows.toList().reversed) removeRow(r)];
    return () {
      for (final u in undos.reversed) {
        u();
      }
    };
  }

  /// Ticks or unticks every row.
  void selectAll(bool v) {
    for (final r in rows()) {
      selection[r.key] = v;
    }
    _touch();
  }

  /// "No date": estimated from the category.
  void skipDate() {
    final p = products.where((x) => x.id == awaitingDateFor).firstOrNull;
    awaitingDateFor = null;
    if (p != null && p.dateSource != DateSource.code) {
      p
        ..skipDate = true
        ..dateState = ShotState.done;
    }
    _touch();
  }

  Future<void> _readProduct(BatchProduct p) async {
    try {
      final raw = await _proc.scanBarcode(p.barcodePath!);
      if (raw != null) {
        final code = parseBarcode(raw);
        p.ean = code.gtin;
        // GS1 codes (fresh meat, cheese counters) carry the date themselves.
        final d = code.useBy ?? code.bestBefore;
        if (d != null && p.datePath == null) {
          p
            ..expiry = d
            ..dateType = code.useBy != null ? DateType.useBy : DateType.bestBefore
            ..dateSource = DateSource.code
            ..dateState = ShotState.done;
        }
        if (p.ean != null) {
          final info = await _proc.lookup(p.ean!);
          if (info != null) {
            p
              ..name = info.name
              ..brand = info.brand
              ..categoryId = info.categoryId ?? guessCategory(tags: info.categoryTags, name: info.name).id
              ..nutrition = info.nutrition
              ..locationType = info.locationType
              ..shelfLifeDays = info.shelfLifeDays
              ..productSource = ProductSource.database;
          }
        }
      }
      if (p.name.isEmpty) {
        final bytes = await XFile(p.barcodePath!).readAsBytes();
        final r = await _proc.aiProduct(bytes);
        if (r != null) {
          p
            ..name = r.name
            ..brand = r.brand
            ..categoryId = r.categoryId
            ..productSource = ProductSource.ai;
        }
      }
      p.productState = p.name.isEmpty ? ShotState.failed : ShotState.done;
    } catch (_) {
      p.productState = ShotState.failed;
    }
  }

  Future<void> _readDate(BatchProduct p) async {
    try {
      final best = bestExpiryCandidate(await _proc.ocr(p.datePath!));
      if (best != null) {
        p
          ..expiry = best.date
          ..dateType = best.dateType ?? p.dateType
          ..dateSource = DateSource.photo;
      } else {
        final r = await _proc.aiDate(await XFile(p.datePath!).readAsBytes());
        if (r != null) {
          p
            ..expiry = r.date
            ..dateType = r.type ?? p.dateType
            ..dateSource = DateSource.ai;
        }
      }
      p.dateState = p.expiry == null ? ShotState.failed : ShotState.done;
    } catch (_) {
      p.dateState = ShotState.failed;
    }
  }

  /// The receipt – before, during or after the photos.
  Future<void> addReceipt(Uint8List bytes) async {
    receiptState = ReceiptState.reading;
    receiptError = null;
    _touch();
    try {
      final lines = await _proc.aiReceipt(bytes);
      receiptLines = [
        for (final l in lines)
          BatchReceiptLine(
            name: l.name,
            quantity: l.quantity,
            unit: l.unit,
            price: l.price,
            isFood: l.isFood,
            categoryId: l.categoryId,
          ),
      ];
      receiptState = ReceiptState.done;
    } catch (e) {
      receiptState = ReceiptState.failed;
      receiptError = '$e';
    }
    _touch();
  }

  void setPairingOn(bool v) {
    pairingOn = v;
    _touch();
  }

  void setPair(String productId, int? lineIndex) {
    manualPairs.removeWhere((k, v) => v != null && v == lineIndex);
    manualPairs[productId] = lineIndex;
    _touch();
  }

  void toggle(String rowKey, bool v) {
    selection[rowKey] = v;
    _touch();
  }

  void edit(String rowKey, PantryItem item) {
    edits[rowKey] = item;
    _touch();
  }

  void removeProduct(String id) {
    products.removeWhere((p) => p.id == id);
    if (awaitingDateFor == id) awaitingDateFor = null;
    _touch();
  }

  void reset() {
    products.clear();
    receiptLines = const [];
    receiptState = ReceiptState.none;
    receiptError = null;
    pairingOn = true;
    manualPairs.clear();
    selection.clear();
    edits.clear();
    awaitingDateFor = null;
    retake = null;
    hiddenLines.clear();
    _touch();
  }

  /// Product id → receipt line (manual choices first, the rest automatic).
  Map<String, int> get pairing {
    if (!pairingOn || receiptLines.isEmpty) return const {};
    final manual = {
      for (final e in manualPairs.entries)
        if (e.value != null) e.key: e.value!,
    };
    final rest = products.where((p) => !manualPairs.containsKey(p.id)).toList();
    final usedLines = manual.values.toSet();
    final free = [for (var i = 0; i < receiptLines.length; i++) if (!usedLines.contains(i)) i];
    final auto = pairWithReceipt(rest, [for (final i in free) receiptLines[i]]);
    return {...manual, for (final e in auto.entries) e.key: free[e.value]};
  }

  /// The review list: every product, then receipt lines without a photo.
  List<ReviewRow> rows({DateTime? now}) {
    final today = now ?? DateTime.now();
    final pairs = pairing;
    final out = <ReviewRow>[];
    for (final p in products) {
      final key = 'p:${p.id}';
      final li = pairs[p.id];
      final line = li == null ? null : receiptLines[li];
      final cat = p.categoryId == 'other' && line != null ? line.categoryId : p.categoryId;
      final loc = p.locationType ?? suggestLocation(cat);
      final expiry = p.expiry ??
          (p.shelfLifeDays != null ? today.add(Duration(days: p.shelfLifeDays!)) : suggestExpiry(cat, loc, today));
      final name = p.name.isNotEmpty ? p.name : (line?.name ?? '');
      final item = PantryItem(
        id: '',
        name: name,
        brand: p.brand,
        categoryId: cat,
        expiryDate: expiry,
        dateType: p.dateType ?? DateType.useBy,
        ean: p.ean,
        locationType: loc,
        locationId: loc.name,
        quantity: line?.quantity ?? 1,
        unit: line?.unit ?? 'ks',
        price: line?.price,
        nutrition: p.nutrition,
        source: p.ean != null ? ItemSource.scan : ItemSource.manual,
      );
      out.add(ReviewRow(
        key: key,
        item: edits[key] ?? item,
        product: p,
        lineIndex: li,
        dateSource: p.expiry == null ? DateSource.estimate : p.dateSource,
        busy: p.busy,
      ));
    }
    final paired = pairs.values.toSet();
    if (pairingOn || products.isEmpty) {
      for (var i = 0; i < receiptLines.length; i++) {
        if (paired.contains(i) || hiddenLines.contains(i)) continue;
        final l = receiptLines[i];
        final key = 'r:$i';
        final loc = suggestLocation(l.categoryId);
        out.add(ReviewRow(
          key: key,
          lineIndex: i,
          dateSource: DateSource.estimate,
          item: edits[key] ??
              PantryItem(
                id: '',
                name: l.name,
                categoryId: l.categoryId,
                expiryDate: suggestExpiry(l.categoryId, loc, today),
                locationType: loc,
                locationId: loc.name,
                quantity: l.quantity,
                unit: l.unit,
                price: l.price,
                source: ItemSource.receipt,
              ),
        ));
      }
    }
    return out;
  }

  bool isSelected(ReviewRow r) =>
      selection[r.key] ?? (r.item.name.isNotEmpty && (r.lineIndex == null || receiptLines[r.lineIndex!].isFood));

  /// Saves the ticked rows; returns how many.
  Future<int> save() async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return 0;
    final repo = ref.read(repositoryProvider);
    final chosen = rows().where((r) => isSelected(r) && !r.busy && r.item.name.trim().isNotEmpty).toList();
    for (final r in chosen) {
      await repo.addItem(h.id, r.item, user);
    }
    reset();
    return chosen.length;
  }
}

final batchJobProvider = NotifierProvider<BatchJob, int>(BatchJob.new);
