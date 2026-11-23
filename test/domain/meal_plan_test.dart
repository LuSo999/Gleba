import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/meal_plan.dart';
import 'package:gleba/domain/models.dart';

void main() {
  test('week starts on Monday; day keys', () {
    expect(weekStart(DateTime(2026, 11, 26, 18)), DateTime(2026, 11, 23));
    expect(dayKey(DateTime(2026, 11, 26)), '2026-11-26');
  });

  test('missing ingredients for shopping: uncooked only, no duplicates, not already listed', () {
    final meals = [
      const Meal(id: 'a', date: '2026-11-24', slot: MealSlot.dinner, title: 'Rizoto', missing: ['Rýže', 'Parmazán']),
      const Meal(id: 'b', date: '2026-11-25', slot: MealSlot.lunch, title: 'Polévka', missing: ['rýže', 'Mrkev']),
      const Meal(id: 'c', date: '2026-11-23', slot: MealSlot.lunch, title: 'Snědeno', missing: ['Chléb'], cooked: true),
    ];
    expect(missingForShopping(meals, ['mrkev']), ['Rýže', 'Parmazán']);
  });

  test('AI ingredient names are matched to fridge items', () {
    final items = [
      PantryItem(id: '1', name: 'Kuřecí prsa', categoryId: 'poultry', expiryDate: DateTime(2026, 11, 25)),
      PantryItem(id: '2', name: 'Rajčata', categoryId: 'vegetables', expiryDate: DateTime(2026, 11, 28)),
    ];
    expect(matchItem('kuřecí prsa', items)?.id, '1');
    expect(matchItem('Rajčata cherry', items)?.id, '2');
    expect(matchItem('Brambory', items), isNull);
  });

  test('round trip', () {
    const m = Meal(id: 'x', date: '2026-11-24', slot: MealSlot.lunch, title: 'Guláš',
        uses: [MealUse(itemId: 'i1', name: 'Maso')], missing: ['Paprika'], notes: 'pikantní');
    final back = Meal.fromMap('x', m.toMap());
    expect((back.title, back.slot, back.uses.single.itemId, back.missing.single, back.notes),
        ('Guláš', MealSlot.lunch, 'i1', 'Paprika', 'pikantní'));
  });
}
