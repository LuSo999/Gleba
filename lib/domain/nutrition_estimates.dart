/// Rough nutrition per 100 g by category, for food without label data
/// (typed in, from a receipt). Values are typical Czech-supermarket averages;
/// they are only an estimate and are marked as such in Health.
library;

import 'models.dart';

// kcal, protein, carbs, fat per 100 g; typical weight of one piece in grams.
const Map<String, (double, double, double, double, double)> _byCategory = {
  'milk': (64, 3.4, 4.8, 3.5, 1000),
  'milkUht': (64, 3.4, 4.8, 3.5, 1000),
  'yogurt': (85, 4.0, 11.0, 3.0, 150),
  'cheeseSoft': (260, 15.0, 3.0, 21.0, 125),
  'cheeseHard': (350, 26.0, 0.5, 27.0, 100),
  'butter': (740, 0.7, 0.7, 82.0, 250),
  'eggs': (143, 12.6, 0.7, 9.9, 55),
  'deli': (250, 15.0, 2.0, 20.0, 100),
  'poultry': (165, 23.0, 0.0, 7.5, 500),
  'fish': (140, 20.0, 0.0, 6.0, 250),
  'meat': (220, 19.0, 0.0, 16.0, 500),
  'rootVeg': (60, 1.5, 12.0, 0.2, 1000),
  'vegetables': (25, 1.2, 4.0, 0.3, 300),
  'fruit': (55, 0.7, 13.0, 0.3, 150),
  'bread': (250, 8.5, 48.0, 2.5, 60),
  'drinks': (40, 0.2, 9.5, 0.0, 500),
  'sauces': (150, 2.0, 15.0, 9.0, 300),
  'canned': (110, 6.0, 14.0, 3.0, 400),
  'dry': (350, 11.0, 70.0, 2.0, 500),
  'sweets': (480, 6.0, 60.0, 24.0, 100),
  'frozen': (150, 8.0, 15.0, 6.0, 400),
  'leftovers': (150, 8.0, 15.0, 6.0, 300),
  'readyMeal': (160, 8.0, 18.0, 6.0, 350),
  'other': (150, 5.0, 20.0, 5.0, 150),
};

(double, double, double, double, double) _of(String categoryId) => _byCategory[categoryId] ?? _byCategory['other']!;

/// Estimated nutrition per 100 g for [categoryId].
Nutrition estimatedNutrition(String categoryId) {
  final (kcal, protein, carbs, fat, _) = _of(categoryId);
  return Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat);
}

/// Typical weight of one piece ("1 ks") of food in [categoryId], in grams.
double typicalPieceGrams(String categoryId) => _of(categoryId).$5;
