import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/open_food_facts.dart';
import 'data/product_lookup.dart';
import 'data/repository.dart';
import 'domain/models.dart';
import 'domain/notification_rules.dart';

/// Overridden in main() with the Firebase or demo implementation.
final authServiceProvider = Provider<AuthService>((ref) => throw UnimplementedError());
final repositoryProvider = Provider<GlebaRepository>((ref) => throw UnimplementedError());
final isDemoProvider = Provider<bool>((ref) => false);
final sharedPrefsProvider = Provider<SharedPreferences?>((ref) => null);

final productLookupProvider = Provider<ProductLookup>(
  (ref) => ProductLookup(ref.watch(repositoryProvider), OpenFoodFactsClient()),
);

final userProvider = StreamProvider<GlebaUser?>((ref) => ref.watch(authServiceProvider).userChanges());

final householdsProvider = StreamProvider<List<Household>>((ref) {
  final user = ref.watch(userProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchHouseholds(user.uid);
});

class ActiveHouseholdId extends Notifier<String?> {
  static const _key = 'activeHousehold';

  @override
  String? build() => ref.read(sharedPrefsProvider)?.getString(_key);

  void select(String id) {
    state = id;
    ref.read(sharedPrefsProvider)?.setString(_key, id);
  }
}

final activeHouseholdIdProvider = NotifierProvider<ActiveHouseholdId, String?>(ActiveHouseholdId.new);

/// The selected household, falling back to the first one available.
final activeHouseholdProvider = Provider<Household?>((ref) {
  final list = ref.watch(householdsProvider).value ?? const [];
  if (list.isEmpty) return null;
  final id = ref.watch(activeHouseholdIdProvider);
  return list.where((h) => h.id == id).firstOrNull ?? list.first;
});

final itemsProvider = StreamProvider<List<PantryItem>>((ref) {
  final h = ref.watch(activeHouseholdProvider);
  if (h == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchActiveItems(h.id);
});

/// Active items of *all* the user's households – notifications cover every
/// household, not only the one currently shown.
final allItemsProvider = StreamProvider<List<PantryItem>>((ref) {
  final households = ref.watch(householdsProvider).value ?? const [];
  if (households.isEmpty) return Stream.value(const []);
  final repo = ref.watch(repositoryProvider);
  final latest = <String, List<PantryItem>>{};
  final controller = StreamController<List<PantryItem>>();
  final subs = [
    for (final h in households)
      repo.watchActiveItems(h.id).listen((items) {
        latest[h.id] = [for (final i in items) i.withHousehold(h.id)];
        controller.add(latest.values.expand((l) => l).toList());
      }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });
  return controller.stream;
});

final notificationRulesProvider = StreamProvider<List<NotificationRule>>((ref) {
  final user = ref.watch(userProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchNotificationRules(user.uid);
});

final notificationPrefsProvider = StreamProvider<NotificationPrefs>((ref) {
  final user = ref.watch(userProvider).value;
  if (user == null) return Stream.value(const NotificationPrefs());
  return ref.watch(repositoryProvider).watchNotificationPrefs(user.uid);
});

class AppSettings {
  const AppSettings({this.locale, this.animations = true, this.partialConsumption = true});

  final Locale? locale;
  final bool animations;
  final bool partialConsumption;

  Duration anim(Duration d) => animations ? d : Duration.zero;
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences? get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final lang = _prefs?.getString('locale');
    return AppSettings(
      locale: lang == null ? null : Locale(lang),
      animations: _prefs?.getBool('animations') ?? true,
      partialConsumption: _prefs?.getBool('partialConsumption') ?? true,
    );
  }

  void setLocale(Locale? l) {
    l == null ? _prefs?.remove('locale') : _prefs?.setString('locale', l.languageCode);
    state = AppSettings(locale: l, animations: state.animations, partialConsumption: state.partialConsumption);
  }

  void setAnimations(bool v) {
    _prefs?.setBool('animations', v);
    state = AppSettings(locale: state.locale, animations: v, partialConsumption: state.partialConsumption);
  }

  void setPartialConsumption(bool v) {
    _prefs?.setBool('partialConsumption', v);
    state = AppSettings(locale: state.locale, animations: state.animations, partialConsumption: v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
