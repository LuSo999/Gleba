/// Who ate what: splitting food between people and per-person totals.
library;

import 'history.dart';
import 'models.dart';

/// Cut positions (0..1, ascending) splitting the bar evenly for [n] people.
List<double> evenCuts(int n) => [for (var i = 1; i < n; i++) i / n];

/// Shares (summing to 1) from the cut positions of the slider.
List<double> sharesFromCuts(List<double> cuts) {
  final bounds = [0.0, ...cuts, 1.0];
  return [for (var i = 0; i < bounds.length - 1; i++) bounds[i + 1] - bounds[i]];
}

/// Moves cut [i] to [value], keeping at least [minShare] for everyone.
List<double> moveCut(List<double> cuts, int i, double value, {double minShare = 0.05}) {
  final lo = (i == 0 ? 0.0 : cuts[i - 1]) + minShare;
  final hi = (i == cuts.length - 1 ? 1.0 : cuts[i + 1]) - minShare;
  // Snap to 5 % steps – fine enough for "who ate how much".
  final snapped = (value * 20).round() / 20;
  return [...cuts]..[i] = snapped.clamp(lo, hi).toDouble();
}

/// The eaters map stored with the event; ids in the order shown.
Map<String, double> eatersFrom(List<String> ids, List<double> cuts) {
  final shares = sharesFromCuts(cuts);
  return {for (var i = 0; i < ids.length; i++) ids[i]: double.parse(shares[i].toStringAsFixed(3))};
}

class EaterTotal {
  EaterTotal(this.id);

  final String id;

  /// Items eaten, counting shares (half a pizza = 0.5).
  double items = 0;
  double grams = 0;
  double kcal = 0;
}

/// Per-person totals of the eaten food in [events], biggest eater first.
/// Older events without [HistoryEvent.eaters] count for the one who tapped.
List<EaterTotal> eaterTotals(Iterable<HistoryEvent> events) {
  final out = <String, EaterTotal>{};
  for (final e in events) {
    if (e.type != HistoryType.consumed || e.cookedInto != null) continue;
    final eaters = e.eaters ?? (e.by == null ? null : {e.by!: 1.0});
    if (eaters == null) continue;
    for (final entry in eaters.entries) {
      final t = out.putIfAbsent(entry.key, () => EaterTotal(entry.key));
      t.items += entry.value;
      if (e.grams != null) {
        t.grams += e.grams! * entry.value;
        final kcal = e.nutrition?.kcal;
        if (kcal != null) t.kcal += kcal * e.grams! * entry.value / 100;
      }
    }
  }
  return out.values.toList()..sort((a, b) => b.items.compareTo(a.items));
}

/// Nutrition per 100 g of a dish cooked from [ingredients] (item + grams
/// used); null unless every ingredient has nutrition data.
Nutrition? cookedNutrition(List<(PantryItem, double)> ingredients) {
  final total = ingredients.fold<double>(0, (s, x) => s + x.$2);
  if (total <= 0 || ingredients.any((x) => x.$1.nutrition == null)) return null;
  double? sum(double? Function(Nutrition n) f) {
    var s = 0.0;
    for (final (item, g) in ingredients) {
      final v = f(item.nutrition!);
      if (v == null) return null;
      s += v * g / 100;
    }
    return s * 100 / total;
  }

  return Nutrition(
    kcal: sum((n) => n.kcal),
    protein: sum((n) => n.protein),
    carbs: sum((n) => n.carbs),
    fat: sum((n) => n.fat),
    sugar: sum((n) => n.sugar),
    fiber: sum((n) => n.fiber),
    salt: sum((n) => n.salt),
    packageGrams: total,
  );
}
