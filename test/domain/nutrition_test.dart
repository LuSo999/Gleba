import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/data/open_food_facts.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/services/health_service.dart';
import 'package:health/health.dart';

void main() {
  test('nutrition from Open Food Facts', () {
    final p = parseOffResponse('8594001021499', {
      'status': 1,
      'product': {
        'product_name': 'Bílý jogurt',
        'nutriments': {'energy-kcal_100g': 60, 'proteins_100g': 4.5, 'carbohydrates_100g': '5', 'fat_100g': 3},
        'serving_quantity': '150',
        'product_quantity': 150,
      },
    }, 'cs')!;
    final n = p.nutrition!;
    expect((n.kcal, n.protein, n.carbs, n.fat, n.servingGrams, n.packageGrams), (60.0, 4.5, 5.0, 3.0, 150.0, 150.0));
    // kJ only → converted to kcal
    final kj = parseOffResponse('1', {'status': 1, 'product': {'product_name': 'X', 'nutriments': {'energy_100g': 418.4}}}, 'cs');
    expect(kj!.nutrition!.kcal!.round(), 100);
    expect(parseOffResponse('1', {'status': 1, 'product': {'product_name': 'X'}}, 'cs')!.nutrition, isNull);
  });

  test('grams eaten and values for a portion', () {
    const n = Nutrition(kcal: 60, protein: 4.5, servingGrams: 150);
    PantryItem item(String unit) =>
        PantryItem(id: 'a', name: 'J', categoryId: 'yogurt', expiryDate: DateTime(2026), unit: unit, nutrition: n);
    expect(gramsEaten(item('ks'), 1), 150);
    expect(gramsEaten(item('g'), 200), 200);
    expect(gramsEaten(item('kg'), 0.5), 500);
    final v = n.forGrams(150);
    expect((v.kcal, v.protein), (90.0, 6.75));
  });

  test('meal type by time of day', () {
    expect(HealthService.mealTypeAt(DateTime(2026, 1, 1, 7)), MealType.BREAKFAST);
    expect(HealthService.mealTypeAt(DateTime(2026, 1, 1, 12)), MealType.LUNCH);
    expect(HealthService.mealTypeAt(DateTime(2026, 1, 1, 19)), MealType.DINNER);
    expect(HealthService.mealTypeAt(DateTime(2026, 1, 1, 16)), MealType.SNACK);
  });

  test('nutrition survives the item round trip', () {
    final i = PantryItem(id: 'a', name: 'J', categoryId: 'yogurt', expiryDate: DateTime(2026), nutrition: const Nutrition(kcal: 60));
    expect(PantryItem.fromMap('a', i.toMap()).nutrition!.kcal, 60);
  });
}
