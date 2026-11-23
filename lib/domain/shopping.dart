/// Shared shopping list and "always keep at least N" stock rules.
library;

import 'models.dart';

class ShoppingEntry {
  const ShoppingEntry({
    required this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.categoryId = 'other',
    this.done = false,
    this.productKey,
    this.byName,
    this.auto = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final double? quantity;
  final String? unit;
  final String categoryId;
  final bool done;

  /// Links the entry to a product (EAN or normalised name), so restocking
  /// doesn't add the same thing twice.
  final String? productKey;
  final String? byName;

  /// Added automatically by a stock rule.
  final bool auto;
  final DateTime? createdAt;

  Map<String, Object?> toMap() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'categoryId': categoryId,
        'done': done,
        'productKey': productKey,
        'byName': byName,
        'auto': auto,
      };

  factory ShoppingEntry.fromMap(String id, Map<String, Object?> m) {
    DateTime? created;
    try {
      created = (m['createdAt'] as dynamic)?.toDate() as DateTime?;
    } catch (_) {}
    return ShoppingEntry(
      id: id,
      name: (m['name'] as String?) ?? '',
      quantity: (m['quantity'] as num?)?.toDouble(),
      unit: m['unit'] as String?,
      categoryId: (m['categoryId'] as String?) ?? 'other',
      done: (m['done'] as bool?) ?? false,
      productKey: m['productKey'] as String?,
      byName: m['byName'] as String?,
      auto: (m['auto'] as bool?) ?? false,
      createdAt: created ?? (m['createdAt'] is DateTime ? m['createdAt'] as DateTime : null),
    );
  }
}

/// "Always have at least [minQuantity] of this."
class StockRule {
  const StockRule({required this.productKey, required this.name, required this.minQuantity, this.unit = 'ks', this.categoryId = 'other'});

  final String productKey;
  final String name;
  final double minQuantity;
  final String unit;
  final String categoryId;

  Map<String, Object?> toMap() =>
      {'productKey': productKey, 'name': name, 'minQuantity': minQuantity, 'unit': unit, 'categoryId': categoryId};

  factory StockRule.fromMap(Map<String, Object?> m) => StockRule(
        productKey: (m['productKey'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        minQuantity: (m['minQuantity'] as num?)?.toDouble() ?? 1,
        unit: (m['unit'] as String?) ?? 'ks',
        categoryId: (m['categoryId'] as String?) ?? 'other',
      );
}

/// Same product = same EAN, or (without EAN) the same name ignoring case,
/// accents-insensitive spacing and punctuation.
String productKeyOf(PantryItem item) => item.ean != null && item.ean!.isNotEmpty ? 'ean:${item.ean}' : nameKey(item.name);

String nameKey(String name) =>
    'name:${name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim()}';

/// How much of the product is still at home.
double stockOf(String productKey, Iterable<PantryItem> items) => items
    .where((i) => i.status == ItemStatus.active && productKeyOf(i) == productKey)
    .fold(0, (sum, i) => sum + i.quantity);

/// Rules that are below their minimum and not already on the (unbought) list.
List<StockRule> restockNeeded(List<StockRule> rules, Iterable<PantryItem> items, List<ShoppingEntry> list) => [
      for (final r in rules)
        if (stockOf(r.productKey, items) < r.minQuantity &&
            !list.any((e) => !e.done && (e.productKey == r.productKey || nameKey(e.name) == nameKey(r.name))))
          r,
    ];
