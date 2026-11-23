import 'package:material_ui/material_ui.dart';

import '../domain/freshness.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}

String categoryLabel(AppLocalizations l, String id) => switch (id) {
        'frozen' => l.catFrozen,
        'leftovers' => l.catLeftovers,
        'readyMeal' => l.catReadyMeal,
        'yogurt' => l.catYogurt,
        'cheeseSoft' => l.catCheeseSoft,
        'cheeseHard' => l.catCheeseHard,
        'butter' => l.catButter,
        'milkUht' => l.catMilkUht,
        'milk' => l.catMilk,
        'eggs' => l.catEggs,
        'deli' => l.catDeli,
        'poultry' => l.catPoultry,
        'fish' => l.catFish,
        'meat' => l.catMeat,
        'rootVeg' => l.catRootVeg,
        'vegetables' => l.catVegetables,
        'fruit' => l.catFruit,
        'bread' => l.catBread,
        'drinks' => l.catDrinks,
        'sauces' => l.catSauces,
        'canned' => l.catCanned,
        'dry' => l.catDry,
        'sweets' => l.catSweets,
        _ => l.catOther,
      };

String locationLabel(AppLocalizations l, LocationType t) => switch (t) {
      LocationType.fridge => l.fridge,
      LocationType.freezer => l.freezer,
      LocationType.pantry => l.pantry,
      LocationType.other => l.otherLocation,
    };

String dateTypeLabel(AppLocalizations l, DateType t) => t == DateType.useBy ? l.useBy : l.bestBefore;

/// "zítra", "za 3 dny", "prošlo včera"…
String relativeExpiry(AppLocalizations l, DateTime expiry, DateTime now) {
  final d = daysLeft(expiry, now);
  return d >= 0 ? l.daysLeft(d) : l.expiredAgo(-d);
}

String formatDate(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatShortDate(d);
