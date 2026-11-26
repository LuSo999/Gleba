/// Same food side by side; the very same food (name, date, unit, place) as one item.
library;

import 'models.dart';
import 'shopping.dart';

String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Items with the same key are the same food and can be one item:
/// same product (EAN or name), same date and date type, unit, place, and
/// the same opened / frozen state.
String mergeKey(PantryItem i) => [
      productKeyOf(i),
      _day(i.expiryDate),
      i.dateType.name,
      i.unit,
      i.locationType?.name ?? '',
      i.isOpened ? 'open' : '',
      i.isFrozen ? 'frozen' : '',
    ].join('|');

/// Groups of active items that should be merged (2+ items each), the item to
/// keep first (the oldest).
List<List<PantryItem>> duplicateGroups(Iterable<PantryItem> items) {
  final by = <String, List<PantryItem>>{};
  for (final i in items) {
    if (i.status != ItemStatus.active || i.id.isEmpty) continue;
    by.putIfAbsent(mergeKey(i), () => []).add(i);
  }
  return [
    for (final g in by.values)
      if (g.length > 1)
        g
          ..sort((a, b) {
            final x = a.addedAt, y = b.addedAt;
            if (x == null || y == null) return a.id.compareTo(b.id);
            return x.compareTo(y);
          }),
  ];
}

/// The merged item: quantities (and prices) added up.
PantryItem mergedItem(PantryItem keep, List<PantryItem> others) {
  final all = [keep, ...others];
  final prices = all.where((i) => i.price != null);
  return keep.copyWith(
    quantity: all.fold<double>(0, (s, i) => s + i.quantity),
    price: prices.isEmpty ? null : prices.fold<double>(0, (s, i) => s + i.price!),
    clearPrice: prices.isEmpty,
    nutrition: keep.nutrition ?? others.map((o) => o.nutrition).whereType<Nutrition>().firstOrNull,
    runningLow: all.any((i) => i.runningLow),
  );
}

/// Keeps the (urgency) order but pulls items with the same name together:
/// each name appears where its most urgent item is.
List<PantryItem> groupSameNames(List<PantryItem> sorted) {
  final by = <String, List<PantryItem>>{};
  for (final i in sorted) {
    by.putIfAbsent(nameKey(i.name), () => []).add(i);
  }
  final seen = <String>{};
  return [
    for (final i in sorted)
      if (seen.add(nameKey(i.name))) ...by[nameKey(i.name)]!,
  ];
}
