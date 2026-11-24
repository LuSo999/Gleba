/// A single entry in a household's history (also the source for statistics).
library;

import 'models.dart';

/// Id used in [HistoryEvent.eaters] for guests / anyone outside the household.
const othersEater = 'others';

enum HistoryType { added, consumed, discarded, opened, frozen, edited, restored, deleted }

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
    this.daysLeft,
    this.eaters,
    this.grams,
    this.nutrition,
    this.cookedInto,
  });

  /// Used up as an ingredient of this dish (not eaten by anyone yet).
  final String? cookedInto;

  /// Who ate it: member uid (or [othersEater]) → share 0..1, summing to 1.
  final Map<String, double>? eaters;

  /// Grams eaten in total and the food's nutrition per 100 g – lets each
  /// eater's own phone write their share to Health Connect.
  final double? grams;
  final Nutrition? nutrition;

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

  /// For removals: days left until the date when it was eaten / thrown away
  /// (negative = after the date).
  final int? daysLeft;

  /// Eaten or thrown away – can be put back into the fridge.
  bool get isRemoval => type == HistoryType.consumed || type == HistoryType.discarded;

  /// Can be put back into the fridge from the history.
  bool get canPutBack => isRemoval || type == HistoryType.deleted;

  factory HistoryEvent.forItem(PantryItem item, HistoryType type,
          {String? by, String? byName, double? quantity, DateTime? at, Map<String, double>? eaters, String? cookedInto}) =>
      HistoryEvent(
        cookedInto: cookedInto,
        eaters: eaters,
        grams: eaters == null ? null : gramsEaten(item, quantity ?? item.quantity),
        nutrition: eaters == null ? null : item.nutrition,
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
        'daysLeft': daysLeft,
        if (eaters != null) 'eaters': eaters,
        if (grams != null) 'grams': grams,
        if (nutrition != null) 'nutrition': nutrition!.toMap(),
        if (cookedInto != null) 'cookedInto': cookedInto,
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
      daysLeft: (m['daysLeft'] as num?)?.toInt(),
      eaters: m['eaters'] is Map
          ? {
              for (final e in (m['eaters'] as Map).entries)
                if (e.value is num) '${e.key}': (e.value as num).toDouble(),
            }
          : null,
      grams: (m['grams'] as num?)?.toDouble(),
      nutrition: Nutrition.fromMap(m['nutrition']),
      cookedInto: m['cookedInto'] as String?,
    );
  }
}
