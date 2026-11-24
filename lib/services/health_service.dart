import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../domain/models.dart';

enum HealthAvailability { available, needsInstall, unavailable }

/// Writes eaten food to Health Connect (and through it to Samsung Health,
/// which syncs with Health Connect). Android only, opt-in.
class HealthService {
  HealthService._();

  static final instance = HealthService._();
  final _health = Health();
  bool _configured = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthAvailability> availability() async {
    if (!supported) return HealthAvailability.unavailable;
    await _configure();
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HealthAvailability.needsInstall,
      _ => HealthAvailability.unavailable,
    };
  }

  Future<void> install() => _health.installHealthConnect();

  /// Asks for permission to write nutrition. true = allowed.
  Future<bool> enable() async {
    if (await availability() != HealthAvailability.available) return false;
    try {
      return await _health.requestAuthorization([HealthDataType.NUTRITION], permissions: [HealthDataAccess.WRITE]);
    } catch (e) {
      debugPrint('Health Connect authorization failed: $e');
      return false;
    }
  }

  /// Breakfast / lunch / dinner / snack by the time of day.
  static MealType mealTypeAt(DateTime t) => switch (t.hour) {
        >= 5 && < 10 => MealType.BREAKFAST,
        >= 11 && < 15 => MealType.LUNCH,
        >= 17 && < 22 => MealType.DINNER,
        _ => MealType.SNACK,
      };

  /// [nutrition] overrides the item's (e.g. a category estimate; then
  /// [estimated] marks the entry's name).
  Future<bool> writeEaten(PantryItem item, double grams, {DateTime? at, Nutrition? nutrition, bool estimated = false}) async {
    final n = nutrition ?? item.nutrition;
    if (n == null || !supported) return false;
    await _configure();
    final v = n.forGrams(grams);
    final now = at ?? DateTime.now();
    try {
      return await _health.writeMeal(
        mealType: mealTypeAt(now),
        startTime: now.subtract(const Duration(minutes: 1)),
        endTime: now,
        name: estimated ? '${item.name} (~)' : item.name,
        caloriesConsumed: v.kcal,
        protein: v.protein,
        carbohydrates: v.carbs,
        fatTotal: v.fat,
        sugar: v.sugar,
        fiber: v.fiber,
        // Health Connect stores sodium; salt is ~40 % sodium.
        sodium: v.salt == null ? null : v.salt! * 0.4,
      );
    } catch (e) {
      debugPrint('Health Connect write failed: $e');
      return false;
    }
  }
}
