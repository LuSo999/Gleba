/// Default shelf-life table and category heuristics.
///
/// Values are conservative approximations based on USDA FoodKeeper (public
/// domain) storage guidance, adapted to Czech product categories. They are only
/// used as *suggestions* when the package date is unknown, and are overridden by
/// what Gleba learns from real data (median per EAN / category).
library;

import 'models.dart';

class FoodCategory {
  const FoodCategory({
    required this.id,
    required this.emoji,
    required this.defaultLocation,
    this.fridgeDays,
    this.freezerDays,
    this.pantryDays,
    this.afterOpeningDays,
    this.keywords = const [],
  });

  final String id;
  final String emoji;
  final LocationType defaultLocation;
  final int? fridgeDays;
  final int? freezerDays;
  final int? pantryDays;

  /// Days an opened package keeps in the fridge.
  final int? afterOpeningDays;

  /// Lower-case substrings matched against Open Food Facts category tags and
  /// the product name (CZ + EN). The first matching category in [foodCategories]
  /// wins, so more specific categories come first.
  final List<String> keywords;

  int? daysIn(LocationType location) => switch (location) {
        LocationType.fridge => fridgeDays,
        LocationType.freezer => freezerDays,
        LocationType.pantry => pantryDays,
        LocationType.other => pantryDays ?? fridgeDays,
      };
}

const _f = LocationType.fridge, _z = LocationType.freezer, _p = LocationType.pantry;

/// Order matters: specific before generic.
const List<FoodCategory> foodCategories = [
  FoodCategory(id: 'frozen', emoji: '🧊', defaultLocation: _z, freezerDays: 180,
      keywords: ['frozen', 'mražen', 'mrazen', 'zmrzlin', 'ice-cream', 'ice cream', 'nanuk']),
  FoodCategory(id: 'leftovers', emoji: '🍲', defaultLocation: _f, fridgeDays: 3, freezerDays: 90,
      keywords: ['zbytk', 'leftover', 'guláš', 'gulas', 'polévk', 'polevk', 'soup']),
  FoodCategory(id: 'readyMeal', emoji: '🍱', defaultLocation: _f, fridgeDays: 4, freezerDays: 90, afterOpeningDays: 2,
      keywords: ['ready-meal', 'meals', 'hotové jídlo', 'hotove jidlo', 'pomazánk', 'pomazank', 'spread', 'hummus']),
  FoodCategory(id: 'yogurt', emoji: '🍶', defaultLocation: _f, fridgeDays: 14, freezerDays: 60, afterOpeningDays: 3,
      keywords: ['yogurt', 'yoghurt', 'jogurt', 'kefir', 'skyr', 'fermented-milk', 'zakysan', 'pudding', 'puding', 'dezert']),
  FoodCategory(id: 'cheeseSoft', emoji: '🧀', defaultLocation: _f, fridgeDays: 7, freezerDays: 90, afterOpeningDays: 5,
      keywords: ['cottage', 'tvaroh', 'mozzarella', 'ricotta', 'mascarpone', 'cream-cheese', 'cream cheese', 'žervé',
          'zerve', 'lučina', 'lucina', 'fresh-cheese', 'smetan', 'cream']),
  FoodCategory(id: 'cheeseHard', emoji: '🧀', defaultLocation: _f, fridgeDays: 30, freezerDays: 180, afterOpeningDays: 21,
      keywords: ['cheese', 'sýr', 'syr', 'eidam', 'gouda', 'parmez', 'parmesan', 'ementál', 'emental', 'hermelín', 'niva']),
  FoodCategory(id: 'butter', emoji: '🧈', defaultLocation: _f, fridgeDays: 30, freezerDays: 270, afterOpeningDays: 30,
      keywords: ['butter', 'máslo', 'maslo', 'margarin', 'rama']),
  FoodCategory(id: 'milkUht', emoji: '🥛', defaultLocation: _p, pantryDays: 90, fridgeDays: 90, afterOpeningDays: 4,
      keywords: ['uht', 'trvanlivé mléko', 'trvanlive mleko', 'plant-milk', 'plant-based-milk', 'rostlinn', 'ovesný nápoj']),
  FoodCategory(id: 'milk', emoji: '🥛', defaultLocation: _f, fridgeDays: 7, freezerDays: 90, afterOpeningDays: 3,
      keywords: ['milk', 'mléko', 'mleko', 'dairies', 'dairy']),
  FoodCategory(id: 'eggs', emoji: '🥚', defaultLocation: _f, fridgeDays: 28, pantryDays: 21,
      keywords: ['egg', 'vejce', 'vajíčk', 'vajick']),
  FoodCategory(id: 'deli', emoji: '🥓', defaultLocation: _f, fridgeDays: 14, freezerDays: 60, afterOpeningDays: 5,
      keywords: ['en:hams', ' ham', 'šunk', 'sunk', 'salám', 'salam', 'sausage', 'klobás', 'klobas', 'párk', 'park', 'slanin',
          'bacon', 'prepared-meats', 'deli', 'uzenin', 'pršut', 'prosciutto']),
  FoodCategory(id: 'poultry', emoji: '🍗', defaultLocation: _f, fridgeDays: 2, freezerDays: 270,
      keywords: ['poultr', 'chicken', 'kuře', 'kure', 'kuřecí', 'kureci', 'krůt', 'krut', 'turkey', 'kachn', 'duck']),
  FoodCategory(id: 'fish', emoji: '🐟', defaultLocation: _f, fridgeDays: 2, freezerDays: 180,
      keywords: ['fish', 'ryb', 'losos', 'salmon', 'treska', 'en:cod', 'seafood', 'krevet', 'shrimp']),
  FoodCategory(id: 'meat', emoji: '🥩', defaultLocation: _f, fridgeDays: 3, freezerDays: 180, afterOpeningDays: 2,
      keywords: ['meat', 'maso', 'vepřov', 'veprov', 'hověz', 'hovez', 'mleté', 'mlete', 'beef', 'pork', 'steak',
          'kotlet', 'řízek', 'rizek']),
  FoodCategory(id: 'rootVeg', emoji: '🧅', defaultLocation: _p, pantryDays: 30, fridgeDays: 30,
      keywords: ['onion', 'cibul', 'česnek', 'cesnek', 'garlic', 'brambor', 'potato', 'batát', 'batat', 'dýně', 'dyne']),
  FoodCategory(id: 'vegetables', emoji: '🥬', defaultLocation: _f, fridgeDays: 7, freezerDays: 240,
      keywords: ['vegetable', 'zelenin', 'rajč', 'rajc', 'tomato', 'okurk', 'cucumber', 'paprik', 'pepper', 'mrkev',
          'carrot', 'brokol', 'broccoli', 'špenát', 'spenat', 'lettuce', 'hlávkový', 'cuketa', 'zucchini', 'houb',
          'mushroom', 'žampion', 'zampion']),
  FoodCategory(id: 'fruit', emoji: '🍎', defaultLocation: _f, fridgeDays: 14, pantryDays: 5, freezerDays: 240,
      keywords: ['fruit', 'ovoce', 'jabl', 'apple', 'hrušk', 'hrusk', 'pear', 'jahod', 'strawberr', 'borůvk', 'boruvk',
          'blueberr', 'hrozn', 'grape', 'citron', 'lemon', 'pomeranč', 'pomeranc', 'orange', 'banán', 'banan', 'kiwi']),
  FoodCategory(id: 'bread', emoji: '🍞', defaultLocation: _p, pantryDays: 4, fridgeDays: 7, freezerDays: 90,
      keywords: ['bread', 'chléb', 'chleb', 'chleba', 'rohlík', 'rohlik', 'pečivo', 'pecivo', 'bagel', 'toast',
          'bageta', 'baguette', 'koláč', 'kolac', 'buchta']),
  FoodCategory(id: 'drinks', emoji: '🧃', defaultLocation: _p, pantryDays: 180, fridgeDays: 180, afterOpeningDays: 5,
      keywords: ['beverage', 'drink', 'juice', 'džus', 'dzus', 'nápoj', 'napoj', 'limonád', 'limonad', 'water', 'voda',
          'pivo', 'beer', 'víno', 'wine']),
  FoodCategory(id: 'sauces', emoji: '🫙', defaultLocation: _p, pantryDays: 365, fridgeDays: 365, afterOpeningDays: 60,
      keywords: ['sauce', 'omáčk', 'omack', 'ketchup', 'kečup', 'kecup', 'mustard', 'hořčic', 'horcic', 'majonéz',
          'majonez', 'mayonnaise', 'dressing', 'pesto', 'condiment', 'džem', 'dzem', 'jam', 'marmeláda']),
  FoodCategory(id: 'canned', emoji: '🥫', defaultLocation: _p, pantryDays: 730, afterOpeningDays: 4,
      keywords: ['canned', 'konzerv', 'plechov', 'sterilovan', 'pickled', 'nakládan', 'nakladan']),
  FoodCategory(id: 'dry', emoji: '🌾', defaultLocation: _p, pantryDays: 365,
      keywords: ['pasta', 'těstovin', 'testovin', 'rice', 'rýže', 'ryze', 'flour', 'mouk', 'cereal', 'müsli', 'musli',
          'oat', 'ovesn', 'legume', 'luštěnin', 'lusten', 'čočk', 'cocka', 'fazol', 'bean', 'cukr', 'sugar', 'sůl',
          'coffee', 'káva', 'kava', 'tea', 'čaj']),
  FoodCategory(id: 'sweets', emoji: '🍫', defaultLocation: _p, pantryDays: 180,
      keywords: ['chocolate', 'čokolád', 'cokolad', 'sušenk', 'susenk', 'biscuit', 'cookie', 'candy', 'bonbon',
          'snack', 'chips', 'brambůrk', 'bramburk', 'oříšk', 'orisk', 'nut']),
  FoodCategory(id: 'other', emoji: '📦', defaultLocation: _f, fridgeDays: 7, freezerDays: 90, pantryDays: 90,
      afterOpeningDays: 3),
];

final Map<String, FoodCategory> _byId = {for (final c in foodCategories) c.id: c};

FoodCategory categoryById(String? id) => _byId[id] ?? _byId['other']!;

/// Guesses a Gleba category from Open Food Facts tags and/or a product name.
/// Tags are checked first because they are more reliable than names.
FoodCategory guessCategory({Iterable<String> tags = const [], String? name}) {
  final tagText = tags.map((t) => t.toLowerCase()).join(' ');
  final nameText = (name ?? '').toLowerCase();
  // "Frozen" in the name beats any tag (frozen spinach is still frozen food).
  final frozen = _byId['frozen']!;
  if (frozen.keywords.any(nameText.contains)) return frozen;
  for (final text in [tagText, nameText]) {
    if (text.isEmpty) continue;
    for (final c in foodCategories) {
      if (c.keywords.any(text.contains)) return c;
    }
  }
  return _byId['other']!;
}

/// Where a new item of [categoryId] should go, unless the user decides otherwise.
LocationType suggestLocation(String categoryId) => categoryById(categoryId).defaultLocation;

/// Default expiry when the package date is unknown.
/// [learnedDays] (median from Gleba data) takes precedence over the table.
DateTime suggestExpiry(String categoryId, LocationType location, DateTime from, {int? learnedDays}) {
  final c = categoryById(categoryId);
  final days = learnedDays ?? c.daysIn(location) ?? c.fridgeDays ?? c.pantryDays ?? 7;
  return dateOnly(from).add(Duration(days: days));
}

/// Expiry after opening: never later than the package date.
DateTime expiryAfterOpening(PantryItem item, DateTime openedAt) {
  final days = categoryById(item.categoryId).afterOpeningDays;
  if (days == null) return item.expiryDate;
  final opened = dateOnly(openedAt).add(Duration(days: days));
  return opened.isBefore(item.expiryDate) ? opened : item.expiryDate;
}

/// Expiry after freezing: freezing extends the life (never shortens it).
DateTime expiryAfterFreezing(PantryItem item, DateTime frozenAt) {
  final days = categoryById(item.categoryId).freezerDays ?? 90;
  final frozen = dateOnly(frozenAt).add(Duration(days: days));
  return frozen.isAfter(item.expiryDate) ? frozen : item.expiryDate;
}
