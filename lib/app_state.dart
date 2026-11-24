import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/open_food_facts.dart';
import 'data/product_lookup.dart';
import 'data/repository.dart';
import 'domain/history.dart';
import 'domain/models.dart';
import 'domain/notification_rules.dart';
import 'domain/shopping.dart';
import 'services/health_sync.dart';

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

final historyProvider = StreamProvider<List<HistoryEvent>>((ref) {
  final h = ref.watch(activeHouseholdProvider);
  if (h == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchHistory(h.id);
});

final shoppingListProvider = StreamProvider<List<ShoppingEntry>>((ref) {
  final h = ref.watch(activeHouseholdProvider);
  if (h == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchShoppingList(h.id);
});

final stockRulesProvider = StreamProvider<List<StockRule>>((ref) {
  final h = ref.watch(activeHouseholdProvider);
  if (h == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchStockRules(h.id);
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
  const AppSettings({
    this.locale,
    this.animations = true,
    this.partialConsumption = true,
    this.shareToOff,
    this.healthWrite = false,
    this.askWhoAte = true,
    this.healthEstimate = true,
  });

  /// Food without label nutrition goes to Health with a category estimate.
  final bool healthEstimate;

  /// "Who ate it?" after Eaten (households with more members).
  final bool askWhoAte;

  /// Log eaten food to Health Connect (Samsung Health).
  final bool healthWrite;

  final Locale? locale;
  final bool animations;
  final bool partialConsumption;

  /// Send products nobody knew to Open Food Facts; null = not asked yet.
  final bool? shareToOff;

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
      shareToOff: _prefs?.getBool('shareToOff'),
      healthWrite: _prefs?.getBool('healthWrite') ?? false,
      askWhoAte: _prefs?.getBool('askWhoAte') ?? true,
      healthEstimate: _prefs?.getBool('healthEstimate') ?? true,
    );
  }

  AppSettings _copy({
    Locale? locale,
    bool clearLocale = false,
    bool? animations,
    bool? partial,
    bool? share,
    bool? health,
    bool? whoAte,
    bool? estimate,
  }) => AppSettings(
    locale: clearLocale ? null : (locale ?? state.locale),
    animations: animations ?? state.animations,
    partialConsumption: partial ?? state.partialConsumption,
    shareToOff: share ?? state.shareToOff,
    healthWrite: health ?? state.healthWrite,
    askWhoAte: whoAte ?? state.askWhoAte,
    healthEstimate: estimate ?? state.healthEstimate,
  );

  void setHealthEstimate(bool v) {
    _prefs?.setBool('healthEstimate', v);
    state = _copy(estimate: v);
  }

  void setAskWhoAte(bool v) {
    _prefs?.setBool('askWhoAte', v);
    state = _copy(whoAte: v);
  }

  void setHealthWrite(bool v) {
    _prefs?.setBool('healthWrite', v);
    state = _copy(health: v);
  }

  void setShareToOff(bool v) {
    _prefs?.setBool('shareToOff', v);
    state = _copy(share: v);
  }

  void setLocale(Locale? l) {
    l == null ? _prefs?.remove('locale') : _prefs?.setString('locale', l.languageCode);
    state = _copy(locale: l, clearLocale: l == null);
  }

  void setAnimations(bool v) {
    _prefs?.setBool('animations', v);
    state = _copy(animations: v);
  }

  void setPartialConsumption(bool v) {
    _prefs?.setBool('partialConsumption', v);
    state = _copy(partial: v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Background upkeep for the active household: keeps my name on it (for
/// "who ate it?") and writes food others marked as eaten by me to Health.
final householdUpkeepProvider = Provider<void>((ref) {
  final h = ref.watch(activeHouseholdProvider);
  final user = ref.watch(userProvider).value;
  final health = ref.watch(settingsProvider.select((s) => s.healthWrite));
  final estimate = ref.read(settingsProvider).healthEstimate;
  if (h == null || user == null) return;
  final repo = ref.read(repositoryProvider);
  final name = user.shortName;
  Future.microtask(() async {
    if (name.isNotEmpty && h.memberNames[user.uid] != name) {
      try {
        await repo.setMemberName(h.id, user.uid, name);
      } catch (_) {}
    }
    if (health) await HealthSync.run(repo, h.id, user.uid, ref.read(sharedPrefsProvider), estimate: estimate);
  });
});
