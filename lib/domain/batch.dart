/// Photographing a whole shopping trip in a row: products from barcode + date
/// photos, optionally paired with the receipt (prices, quantities).
library;

import 'models.dart';

enum ShotState { processing, done, failed }

/// Where a value came from (shown as tags in the review).
enum DateSource { code, photo, ai, estimate }

enum ProductSource { database, ai, receipt, unknown }

/// One product photographed in the series.
class BatchProduct {
  BatchProduct({required this.id, this.barcodePath});

  final String id;
  String? barcodePath;
  String? datePath;

  /// The user tapped "no date" – it is estimated from the category.
  bool skipDate = false;

  ShotState productState = ShotState.processing;
  ShotState dateState = ShotState.processing;

  String? ean;
  String name = '';
  String? brand;
  String categoryId = 'other';
  Nutrition? nutrition;
  LocationType? locationType;
  int? shelfLifeDays;
  ProductSource productSource = ProductSource.unknown;

  DateTime? expiry;
  DateType? dateType;
  DateSource? dateSource;

  bool get busy =>
      productState == ShotState.processing || (!skipDate && datePath != null && dateState == ShotState.processing);
}

/// A receipt line in the series (from the AI receipt reader).
class BatchReceiptLine {
  const BatchReceiptLine({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.isFood,
    required this.categoryId,
  });

  final String name;
  final double quantity;
  final String unit;
  final double? price;
  final bool isFood;
  final String categoryId;
}

String _fold(String s) {
  const from = 'áäčďéěíĺľňóôöřŕšťúůüýžÁÄČĎÉĚÍĹĽŇÓÔÖŘŔŠŤÚŮÜÝŽ';
  const to = 'aacdeeillnooorrstuuuyzAACDEEILLNOOORRSTUUUYZ';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

List<String> _words(String s) =>
    _fold(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3 && !RegExp(r'^\d+$').hasMatch(w)).toList();

/// How well a product name matches a (heavily abbreviated) receipt line,
/// 0..1. Receipts shorten words ("Čist.vlhč.ubr." ~ "Čisticí vlhčené
/// ubrousky"), so words match by a common prefix of at least 3 letters.
double nameSimilarity(String product, String receipt) {
  final a = _words(product), b = _words(receipt);
  if (a.isEmpty || b.isEmpty) return 0;
  double word(String x, String y) {
    var n = 0;
    while (n < x.length && n < y.length && x[n] == y[n]) {
      n++;
    }
    if (n < 3) return 0;
    final shorter = x.length < y.length ? x.length : y.length;
    return n / shorter;
  }

  double side(List<String> from, List<String> to) =>
      from.map((x) => to.map((y) => word(x, y)).fold<double>(0, (m, v) => v > m ? v : m)).fold<double>(0, (s, v) => s + v) /
      from.length;
  // The receipt line is short: weigh how much of it is explained more.
  return 0.35 * side(a, b) + 0.65 * side(b, a);
}

/// Pairs products with receipt lines: best matches first, each used once.
/// Returns product id → line index.
Map<String, int> pairWithReceipt(List<BatchProduct> products, List<BatchReceiptLine> lines, {double threshold = 0.45}) {
  final scored = <(String, int, double)>[
    for (final p in products)
      if (p.name.isNotEmpty)
        for (var i = 0; i < lines.length; i++) (p.id, i, nameSimilarity(p.name, lines[i].name)),
  ]..sort((x, y) => y.$3.compareTo(x.$3));
  final out = <String, int>{};
  final used = <int>{};
  for (final (id, i, s) in scored) {
    if (s < threshold) break;
    if (out.containsKey(id) || used.contains(i)) continue;
    out[id] = i;
    used.add(i);
  }
  return out;
}
