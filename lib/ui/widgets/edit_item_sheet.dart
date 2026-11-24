import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';

/// Edit an item: name, brand, category, place, quantity, date and price.
/// Returns the changed item, or null when cancelled.
Future<PantryItem?> showEditItemSheet(BuildContext context, PantryItem item) => showModalBottomSheet<PantryItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => EditItemSheet(item: item),
    );

class EditItemSheet extends StatefulWidget {
  const EditItemSheet({super.key, required this.item});

  final PantryItem item;

  @override
  State<EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<EditItemSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item.name);
  late final _brand = TextEditingController(text: widget.item.brand ?? '');
  late final _qty = TextEditingController(text: _fmt(widget.item.quantity));
  late final _price = TextEditingController(text: widget.item.price == null ? '' : _fmt(widget.item.price!));
  late String _categoryId = widget.item.categoryId;
  late LocationType _location = _placeOf(widget.item);
  late String _unit = widget.item.unit;
  late DateType _dateType = widget.item.dateType;
  late DateTime _expiry = widget.item.expiryDate;

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  static LocationType _placeOf(PantryItem i) {
    final t = i.locationType ?? suggestLocation(i.categoryId);
    return t == LocationType.other ? LocationType.pantry : t;
  }

  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final i = widget.item;
    final brand = _brand.text.trim();
    final price = _num(_price.text);
    final moved = _location != _placeOf(i);
    Navigator.pop(
      context,
      i.copyWith(
        name: _name.text.trim(),
        brand: brand.isEmpty ? null : brand,
        clearBrand: brand.isEmpty,
        categoryId: _categoryId,
        locationType: _location,
        locationId: moved ? _location.name : i.locationId,
        quantity: _num(_qty.text) ?? i.quantity,
        unit: _unit,
        dateType: _dateType,
        expiryDate: _expiry,
        price: price,
        clearPrice: price == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.editItem, style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l.productName),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').trim().isEmpty ? l.productName : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _brand, decoration: InputDecoration(labelText: l.brand)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.category),
                  items: [
                    for (final c in foodCategories)
                      DropdownMenuItem(value: c.id, child: Text('${c.emoji}  ${categoryLabel(l, c.id)}')),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
                ),
                const SizedBox(height: 12),
                Text(l.location, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                SegmentedButton<LocationType>(
                  segments: [
                    for (final t in [LocationType.fridge, LocationType.freezer, LocationType.pantry])
                      ButtonSegment(value: t, label: Text(locationLabel(l, t))),
                  ],
                  selected: {_location},
                  onSelectionChanged: (s) => setState(() => _location = s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: l.quantity),
                        validator: (v) => (_num(v ?? '') ?? 0) > 0 ? null : l.quantity,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        initialValue: const ['ks', 'g', 'kg', 'ml', 'l'].contains(_unit) ? _unit : 'ks',
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
                    side: BorderSide(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  leading: const Icon(Icons.event),
                  title: Text('${formatDate(context, _expiry)} · ${relativeExpiry(l, _expiry, DateTime.now())}'),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _expiry,
                      firstDate: now.subtract(const Duration(days: 365 * 2)),
                      lastDate: now.add(const Duration(days: 365 * 5)),
                    );
                    if (d != null) setState(() => _expiry = d);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l.priceCzk),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: _save, child: Text(l.save))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
