/// A single entry in a household's history (also the source for statistics).
library;

import 'models.dart';

enum HistoryType { added, consumed, discarded, opened, frozen, edited, restored }

class HistoryEvent {
  const HistoryEvent({
    required this.id,
    required this.itemId,
    required this.type,
    required this.at,
    this.name = '',
    this.categoryId = 'other',
    this.quantity,
    this.unit,
    this.price,
    this.by,
    this.byName,
  });

  final String id;
  final String itemId;
  final HistoryType type;
  final DateTime at;
  final String name;
  final String categoryId;
  final double? quantity;
  final String? unit;
  final double? price;
  final String? by;
  final String? byName;

  /// Eaten or thrown away – can be put back into the fridge.
  bool get isRemoval => type == HistoryType.consumed || type == HistoryType.discarded;

  factory HistoryEvent.forItem(PantryItem item, HistoryType type,
          {String? by, String? byName, double? quantity, DateTime? at}) =>
      HistoryEvent(
        id: '',
        itemId: item.id,
        type: type,
        at: at ?? DateTime.now(),
        name: item.name,
        categoryId: item.categoryId,
        quantity: quantity ?? item.quantity,
        unit: item.unit,
        price: item.price == null || item.quantity == 0
            ? null
            : item.price! * (quantity ?? item.quantity) / item.quantity,
        by: by,
        byName: byName,
      );

  Map<String, Object?> toMap() => {
        'itemId': itemId,
        'type': type.name,
        'at': at,
        'name': name,
        'categoryId': categoryId,
        'quantity': quantity,
        'unit': unit,
        'price': price,
        'by': by,
        'byName': byName,
      };

  factory HistoryEvent.fromMap(String id, Map<String, Object?> m) {
    DateTime at;
    final raw = m['at'];
    if (raw is DateTime) {
      at = raw;
    } else {
      try {
        at = (raw as dynamic).toDate() as DateTime;
      } catch (_) {
        at = DateTime.now(); // pending server timestamp
      }
    }
    return HistoryEvent(
      id: id,
      itemId: (m['itemId'] as String?) ?? '',
      type: HistoryType.values.where((t) => t.name == m['type']).firstOrNull ?? HistoryType.edited,
      at: at,
      name: (m['name'] as String?) ?? '',
      categoryId: (m['categoryId'] as String?) ?? 'other',
      quantity: (m['quantity'] as num?)?.toDouble(),
      unit: m['unit'] as String?,
      price: (m['price'] as num?)?.toDouble(),
      by: m['by'] as String?,
      byName: m['byName'] as String?,
    );
  }
}
