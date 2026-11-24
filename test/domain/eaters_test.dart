import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/eaters.dart';
import 'package:gleba/domain/history.dart';
import 'package:gleba/domain/models.dart';

void main() {
  test('cuts split the bar; handles keep 5 % for everyone and snap to 5 %', () {
    expect(evenCuts(1), isEmpty);
    expect(evenCuts(3), [1 / 3, 2 / 3]);
    expect(sharesFromCuts([0.6]), [0.6, closeTo(0.4, 1e-9)]);
    var cuts = evenCuts(3);
    cuts = moveCut(cuts, 0, 0.71); // can't pass the next handle
    expect(cuts[0], closeTo(2 / 3 - 0.05, 1e-9));
    cuts = moveCut([0.5], 0, 0.42);
    expect(cuts.single, 0.4);
    expect(eatersFrom(['me', 'ája'], [0.6]), {'me': 0.6, 'ája': 0.4});
  });

  test('who ate what: shares, grams, kcal; cooked ingredients and old events', () {
    const n = Nutrition(kcal: 200);
    final ev = [
      HistoryEvent(id: '1', itemId: 'a', type: HistoryType.consumed, at: DateTime(2026), by: 'me',
          eaters: const {'me': 0.5, 'ája': 0.5}, grams: 400, nutrition: n),
      HistoryEvent(id: '2', itemId: 'b', type: HistoryType.consumed, at: DateTime(2026), by: 'ája'), // old: no eaters
      HistoryEvent(id: '3', itemId: 'c', type: HistoryType.consumed, at: DateTime(2026), by: 'me', cookedInto: 'Guláš'),
      HistoryEvent(id: '4', itemId: 'd', type: HistoryType.discarded, at: DateTime(2026), by: 'me'),
    ];
    final t = {for (final x in eaterTotals(ev)) x.id: x};
    expect(t['ája']!.items, 1.5);
    expect(t['me']!.items, 0.5);
    expect(t['me']!.grams, 200);
    expect(t['me']!.kcal, 400);
  });

  test('a cooked dish gets the weighted nutrition of its ingredients', () {
    PantryItem it(double kcal, double g) => PantryItem(
        id: '', name: 'x', categoryId: 'other', expiryDate: DateTime(2026), quantity: g, unit: 'g',
        nutrition: Nutrition(kcal: kcal));
    final n = cookedNutrition([(it(100, 300), 300), (it(500, 100), 100)])!;
    expect(n.kcal, closeTo(200, 1e-9)); // (300 + 500) kcal / 400 g
    expect(n.packageGrams, 400);
    expect(cookedNutrition([(it(100, 300), 300), (PantryItem(id: '', name: 'y', categoryId: 'other', expiryDate: DateTime(2026)), 50)]), isNull);
  });
}
