import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import '../domain/history.dart';
import '../domain/models.dart';
import '../domain/nutrition_estimates.dart';
import 'health_service.dart';

/// Writes to this phone's Health Connect the shares of food that someone
/// else in the household marked as eaten by me ("who ate it?").
class HealthSync {
  static const _key = 'health.syncedEvents';
  static bool _running = false;

  static Future<int> run(GlebaRepository repo, String householdId, String uid, SharedPreferences? prefs,
      {bool estimate = true}) async {
    if (_running || !HealthService.supported) return 0;
    _running = true;
    try {
      final done = {...?prefs?.getStringList(_key)};
      final events = await repo.fetchEvents(householdId, since: DateTime.now().subtract(const Duration(days: 3)));
      var wrote = 0;
      for (final e in events) {
        final share = e.eaters?[uid] ?? 0;
        if (e.type != HistoryType.consumed || e.by == uid || share <= 0) continue;
        final nutrition = e.nutrition ?? (estimate ? estimatedNutrition(e.categoryId) : null);
        if (e.grams == null || nutrition == null || done.contains(e.id)) continue;
        final item = PantryItem(id: e.itemId, name: e.name, categoryId: e.categoryId, expiryDate: e.at);
        if (await HealthService.instance
            .writeEaten(item, e.grams! * share, at: e.at, nutrition: nutrition, estimated: e.nutrition == null)) {
          wrote++;
        }
        done.add(e.id);
      }
      // Keep the list short: only ids of the last few days matter.
      await prefs?.setStringList(_key, done.toList().reversed.take(300).toList());
      return wrote;
    } catch (_) {
      return 0;
    } finally {
      _running = false;
    }
  }
}
