import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_state.dart';
import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../domain/expiry_date_parser.dart';
import '../../domain/gs1_parser.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../../services/ocr_service.dart';
import '../labels.dart';
import '../widgets/burst.dart';

enum AddMode { scan, manual, leftover }

enum _DateOrigin { suggested, code, photo, user }

class AddItemScreen extends ConsumerStatefulWidget {
  const AddItemScreen({super.key, required this.mode});

  final AddMode mode;

  @override
  ConsumerState<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends ConsumerState<AddItemScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _qty = TextEditingController(text: '1');

  late bool _scanning = widget.mode == AddMode.scan;
  bool _lookingUp = false;
  String? _message;
  ProductInfo? _product;

  String? _ean;
  late String _categoryId = widget.mode == AddMode.leftover ? 'leftovers' : 'other';
  LocationType? _location;
  bool _locationTouched = false;
  String _unit = 'ks';
  DateType _dateType = DateType.useBy;
  late DateTime _expiry;
  _DateOrigin _dateOrigin = _DateOrigin.suggested;
  ItemSource _source = ItemSource.manual;

  @override
  void initState() {
    super.initState();
    if (widget.mode == AddMode.leftover) _source = ItemSource.leftover;
    _applyCategory(_categoryId);
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _qty.dispose();
    super.dispose();
  }

  LocationType get _effectiveLocation => _location ?? suggestLocation(_categoryId);

  void _applyCategory(String id) {
    _categoryId = id;
    if (!_locationTouched) _location = suggestLocation(id);
    if (_dateOrigin == _DateOrigin.suggested) {
      _expiry = suggestExpiry(id, _effectiveLocation, DateTime.now(), learnedDays: _product?.shelfLifeDays);
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || !_scanning) return;
    final data = parseBarcode(raw);
    if (data.gtin == null && !data.hasDate) return;
    setState(() {
      _scanning = false;
      _ean = data.gtin;
      _source = ItemSource.scan;
      if (data.hasDate) {
        _expiry = (data.useBy ?? data.bestBefore)!;
        _dateType = data.useBy != null ? DateType.useBy : DateType.bestBefore;
        _dateOrigin = _DateOrigin.code;
        _source = ItemSource.gs1;
      }
    });
    if (data.gtin == null) return;
    if (data.isInStoreCode) {
      setState(() => _message = context.l.inStoreCode);
    }
    final hid = ref.read(activeHouseholdProvider)?.id;
    if (hid == null) return;
    setState(() => _lookingUp = true);
    final info = await ref.read(productLookupProvider).lookup(hid, data.gtin!);
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      _product = info;
      if (info == null) {
        _message ??= context.l.productNotFound;
        return;
      }
      _message = context.l.productFound(info.source == 'household' ? '🏠' : 'Open Food Facts');
      _name.text = info.name;
      _brand.text = info.brand ?? '';
      if (info.locationType != null && !_locationTouched) {
        _location = info.locationType;
        _locationTouched = true;
      }
      _applyCategory(info.categoryId ?? guessCategory(tags: info.categoryTags, name: info.name).id);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (d != null) {
      setState(() {
        _expiry = d;
        _dateOrigin = _DateOrigin.user;
      });
    }
  }

  Future<void> _photoDate() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    final ai = ref.read(aiServiceProvider);
    final photo = await OcrService.capture();
    if (photo == null || !mounted) return;
    List<ExpiryCandidate> candidates;
    try {
      final text = await OcrService.recognize(photo);
      candidates = findExpiryCandidates(text).where((c) => c.score > 0).take(4).toList();
    } catch (e) {
      candidates = const [];
    }
    // On-device reading found nothing → ask the AI, if the user has a key.
    if (candidates.isEmpty && ai.enabledFor(AiFeature.date)) {
      messenger.showSnackBar(SnackBar(content: Text(l.aiReadingDate)));
      try {
        final res = parseDate(await ai.run(AiFeature.date, dateRequest(AiImage(await photo.readAsBytes()), DateTime.now())));
        if (res != null) {
          candidates = [ExpiryCandidate(res.date, 100, dateType: res.type, matched: 'AI')];
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(l.aiError('$e'))));
      }
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.dateNotFound)));
      return;
    }
    var chosen = candidates.first;
    // Ask only when the top two candidates are close calls.
    if (candidates.length > 1 && candidates[1].score >= candidates.first.score - 10) {
      final picked = await showDialog<ExpiryCandidate>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(l.chooseDate),
          children: [
            for (final c in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text('${formatDate(ctx, c.date)}   ·   „${c.matched}“'
                    '${c.dateType == null ? '' : '   (${dateTypeLabel(l, c.dateType!)})'}'),
              ),
          ],
        ),
      );
      if (picked == null) return;
      chosen = picked;
    }
    setState(() {
      _expiry = chosen.date;
      if (chosen.dateType != null) _dateType = chosen.dateType!;
      _dateOrigin = _DateOrigin.photo;
    });
  }

  Future<void> _productFromPhoto() async {
    final l = context.l;
    final messenger = ScaffoldMessenger.of(context);
    final photo = await OcrService.capture();
    if (photo == null) return;
    setState(() => _lookingUp = true);
    try {
      final lang = mounted ? Localizations.localeOf(context).languageCode : 'cs';
      final p = parseProduct(await ref
          .read(aiServiceProvider)
          .run(AiFeature.product, productRequest(AiImage(await photo.readAsBytes()), lang)));
      if (!mounted) return;
      setState(() {
        _name.text = p.name;
        _brand.text = p.brand ?? '';
        _message = null;
        _applyCategory(p.categoryId);
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.aiError('$e'))));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _save({bool next = false}) async {
    if (!_form.currentState!.validate()) return;
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final loc = _effectiveLocation;
    final item = PantryItem(
      id: '',
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      ean: _ean,
      imageUrl: _product?.imageUrl,
      categoryId: _categoryId,
      locationId: loc.name,
      locationType: loc,
      quantity: double.tryParse(_qty.text.replaceAll(',', '.')) ?? 1,
      unit: _unit,
      dateType: _dateType,
      expiryDate: _expiry,
      source: _source,
      frozenAt: loc == LocationType.freezer && _categoryId != 'frozen' ? DateTime.now() : null,
    );
    await ref.read(repositoryProvider).addItem(h.id, item, user);
    if (!mounted) return;
    showBurst(context, categoryById(_categoryId).emoji,
        particles: const ['❄️', '✨'], enabled: ref.read(settingsProvider).animations);
    if (next) {
      setState(() {
        _scanning = true;
        _product = null;
        _message = null;
        _ean = null;
        _name.clear();
        _brand.clear();
        _qty.text = '1';
        _locationTouched = false;
        _dateOrigin = _DateOrigin.suggested;
        _dateType = DateType.useBy;
        _applyCategory('other');
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.mode) {
          AddMode.scan => l.scanBarcode,
          AddMode.manual => l.enterManually,
          AddMode.leftover => l.addLeftover,
        }),
      ),
      body: _scanning
          ? Stack(
              children: [
                MobileScanner(onDetect: _onDetect),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text(l.scanHint, style: const TextStyle(color: Colors.white)),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => _scanning = false),
                    child: Text(l.enterManually),
                  ),
                ),
              ],
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_lookingUp) const LinearProgressIndicator(),
                  if (_message != null)
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
                    ),
                  if (_product?.imageUrl != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(_product!.imageUrl!, height: 120,
                              errorBuilder: (_, _, _) => const SizedBox()),
                        ),
                      ),
                    ),
                  if (_ean != null) Text('EAN $_ean', style: theme.textTheme.labelSmall),
                  if (_product == null &&
                      widget.mode != AddMode.leftover &&
                      ref.watch(aiServiceProvider).enabledFor(AiFeature.product)) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _lookingUp ? null : _productFromPhoto,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(l.productFromPhoto),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    autofocus: widget.mode != AddMode.scan,
                    decoration: InputDecoration(labelText: l.productName),
                    validator: (v) => v == null || v.trim().isEmpty ? '!' : null,
                    onChanged: (v) {
                      // Re-guess the category from the name until a product was found.
                      if (_product == null && widget.mode != AddMode.leftover && v.length > 2) {
                        final g = guessCategory(name: v);
                        if (g.id != 'other' && g.id != _categoryId) setState(() => _applyCategory(g.id));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (widget.mode != AddMode.leftover) ...[
                    TextFormField(controller: _brand, decoration: InputDecoration(labelText: l.brand)),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: InputDecoration(labelText: l.category),
                    isExpanded: true,
                    items: [
                      for (final c in foodCategories)
                        DropdownMenuItem(value: c.id, child: Text('${c.emoji}  ${categoryLabel(l, c.id)}')),
                    ],
                    onChanged: (v) => setState(() => _applyCategory(v!)),
                  ),
                  const SizedBox(height: 12),
                  Text(l.location, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SegmentedButton<LocationType>(
                    segments: [
                      for (final t in [LocationType.fridge, LocationType.freezer, LocationType.pantry])
                        ButtonSegment(value: t, label: Text(locationLabel(l, t))),
                    ],
                    selected: {_effectiveLocation},
                    onSelectionChanged: (s) => setState(() {
                      _location = s.first;
                      _locationTouched = true;
                      _applyCategory(_categoryId);
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qty,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: l.quantity),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          initialValue: _unit,
                          decoration: InputDecoration(labelText: l.unit),
                          items: [for (final u in ['ks', 'g', 'kg', 'ml', 'l']) DropdownMenuItem(value: u, child: Text(u))],
                          onChanged: (v) => setState(() => _unit = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<DateType>(
                    segments: [
                      ButtonSegment(value: DateType.useBy, label: Text(l.useBy)),
                      ButtonSegment(value: DateType.bestBefore, label: Text(l.bestBefore)),
                    ],
                    selected: {_dateType},
                    onSelectionChanged: (s) => setState(() => _dateType = s.first),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    shape: RoundedRectangleBorder(
                        side: BorderSide(color: theme.colorScheme.outline), borderRadius: BorderRadius.circular(4)),
                    leading: const Icon(Icons.event),
                    title: Text('${formatDate(context, _expiry)} · ${relativeExpiry(l, _expiry, DateTime.now())}'),
                    subtitle: switch (_dateOrigin) {
                      _DateOrigin.code => Text(l.dateFromCode),
                      _DateOrigin.photo => Text(l.dateFromPhoto),
                      _DateOrigin.suggested => Text(l.dateSuggested),
                      _DateOrigin.user => null,
                    },
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: _pickDate,
                  ),
                  if (OcrService.supported || ref.watch(aiServiceProvider).enabledFor(AiFeature.date)) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _photoDate,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(l.photoDate),
                    ),
                  ],
                  if (_product != null && (_product!.allergens.isNotEmpty || _product!.nutriScore != null)) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (_product!.nutriScore != null) Chip(label: Text('${l.nutriScore} ${_product!.nutriScore}')),
                      for (final a in _product!.allergens) Chip(avatar: const Text('⚠️'), label: Text(a)),
                    ]),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(l.save)),
                  if (widget.mode == AddMode.scan) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _save(next: true),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text('${l.save} + ${l.scanBarcode.toLowerCase()}'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
