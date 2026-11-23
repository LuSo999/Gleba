/// Household meal plan: what we'll cook on which day, using what from the
/// fridge, and what still needs buying.
library;

import 'models.dart';
import 'shopping.dart' show nameKey;

enum MealSlot { breakfast, lunch, dinner }

class MealUse {
  const MealUse({required this.itemId, required this.name});

  final String itemId;
  final String name;

  Map<String, Object?> toMap() => {'itemId': itemId, 'name': name};
  factory MealUse.fromMap(Map m) => MealUse(itemId: '${m['itemId'] ?? ''}', name: '${m['name'] ?? ''}');
}

class Meal {
  const Meal({
    required this.id,
    required this.date,
    required this.slot,
    required this.title,
    this.uses = const [],
    this.missing = const [],
    this.notes = '',
    this.cooked = false,
    this.byName,
  });

  final String id;

  /// Local day "YYYY-MM-DD".
  final String date;
  final MealSlot slot;
  final String title;
  final List<MealUse> uses;
  final List<String> missing;
  final String notes;
  final bool cooked;
  final String? byName;

  Meal copyWith({String? date, MealSlot? slot, String? title, List<MealUse>? uses, List<String>? missing, String? notes, bool? cooked}) =>
      Meal(
        id: id,
        date: date ?? this.date,
        slot: slot ?? this.slot,
        title: title ?? this.title,
        uses: uses ?? this.uses,
        missing: missing ?? this.missing,
        notes: notes ?? this.notes,
        cooked: cooked ?? this.cooked,
        byName: byName,
      );

  Map<String, Object?> toMap() => {
        'date': date,
        'slot': slot.name,
        'title': title,
        'uses': [for (final u in uses) u.toMap()],
        'missing': missing,
        'notes': notes,
        'cooked': cooked,
        'byName': byName,
      };

  factory Meal.fromMap(String id, Map<String, Object?> m) => Meal(
        id: id,
        date: (m['date'] as String?) ?? '',
        slot: MealSlot.values.where((s) => s.name == m['slot']).firstOrNull ?? MealSlot.dinner,
        title: (m['title'] as String?) ?? '',
        uses: [for (final u in (m['uses'] as List? ?? const [])) if (u is Map) MealUse.fromMap(u)],
        missing: [for (final x in (m['missing'] as List? ?? const [])) '$x'],
        notes: (m['notes'] as String?) ?? '',
        cooked: (m['cooked'] as bool?) ?? false,
        byName: m['byName'] as String?,
      );
}

String dayKey(DateTime d) => d.toIso8601String().substring(0, 10);

DateTime weekStart(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Missing ingredients of not-yet-cooked meals that aren't on the shopping
/// list yet, without duplicates (case/spacing-insensitive).
List<String> missingForShopping(Iterable<Meal> meals, Iterable<String> onList) {
  final seen = {for (final n in onList) nameKey(n)};
  final out = <String>[];
  for (final m in meals.where((m) => !m.cooked)) {
    for (final x in m.missing) {
      final k = nameKey(x);
      if (x.trim().isEmpty || seen.contains(k)) continue;
      seen.add(k);
      out.add(x.trim());
    }
  }
  return out;
}

/// Matches an ingredient name the AI returned to one of our fridge items.
PantryItem? matchItem(String name, Iterable<PantryItem> items) {
  final k = nameKey(name);
  for (final i in items) {
    if (nameKey(i.name) == k) return i;
  }
  for (final i in items) {
    final ik = nameKey(i.name);
    if (ik.contains(k.substring(5)) || k.contains(ik.substring(5))) return i;
  }
  return null;
}
