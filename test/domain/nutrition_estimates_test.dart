import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_tasks.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/domain/nutrition_estimates.dart';

void main() {
  test('every category has an estimate; pieces weigh like the category', () {
    expect(estimatedNutrition('butter').kcal, greaterThan(600));
    expect(estimatedNutrition('unknown-category').kcal, isNotNull);
    final yogurt = PantryItem(id: '', name: 'Jogurt', categoryId: 'yogurt', expiryDate: DateTime(2026), quantity: 2);
    expect(gramsEaten(yogurt, 2), 300); // 2 × 150 g instead of a flat 100 g
  });

  test('nutrition table read by AI: -1 means missing, kcal required', () {
    final n = parseNutrition('{"kcal":389,"protein":13.2,"carbs":60,"sugar":-1,"fat":7,"fiber":-1,"salt":0.1,"packageGrams":500}');
    expect(n.kcal, 389);
    expect(n.sugar, isNull);
    expect(n.packageGrams, 500);
    expect(() => parseNutrition('{"kcal":-1}'), throwsA(anything));
  });
}
