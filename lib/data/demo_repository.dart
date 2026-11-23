import 'dart:async';

import '../domain/history.dart';
import '../domain/models.dart';
import '../domain/notification_rules.dart';
import '../domain/shopping.dart';
import 'repository.dart';

/// In-memory backend used until Firebase is configured, and in widget tests.
/// Lets anyone try the app on the web without an account.
class DemoAuthService implements AuthService {
  final _controller = StreamController<GlebaUser?>.broadcast();
  GlebaUser? _user;

  @override
  Stream<GlebaUser?> userChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  GlebaUser? get currentUser => _user;

  void _set(GlebaUser? u) => _controller.add(_user = u);

  @override
  Future<void> signInWithGoogle() async => _set(const GlebaUser(uid: 'demo', displayName: 'Demo'));

  @override
  Future<void> signInWithEmail(String email, String password) async =>
      _set(GlebaUser(uid: 'demo', email: email, displayName: email.split('@').first));

  @override
  Future<void> registerWithEmail(String email, String password) => signInWithEmail(email, password);

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => _set(null);
}

class DemoRepository implements GlebaRepository {
  DemoRepository({DateTime? now, bool seed = true}) {
    if (seed) _seed(now ?? DateTime.now());
  }

  final _households = <Household>[];
  final _items = <String, Map<String, PantryItem>>{};
  final _products = <String, ProductInfo>{};
  final _invites = <String, InviteInfo>{};
  final _rules = <String, NotificationRule>{};
  final _events = <String, List<HistoryEvent>>{};
  final _shopping = <String, Map<String, ShoppingEntry>>{};
  final _stock = <String, Map<String, StockRule>>{};
  var _prefs = const NotificationPrefs();
  final _changes = StreamController<void>.broadcast();
  var _seq = 0;

  void _seed(DateTime now) {
    _households.add(const Household(id: 'home', name: 'Domov', memberIds: ['demo']));
    final d = dateOnly(now);
    PantryItem it(String name, String cat, int days, LocationType loc,
            {DateType type = DateType.useBy, double q = 1, String unit = 'ks', bool opened = false}) =>
        PantryItem(
          id: 'i${_seq++}',
          name: name,
          categoryId: cat,
          expiryDate: d.add(Duration(days: days)),
          locationType: loc,
          dateType: type,
          quantity: q,
          unit: unit,
          openedAt: opened ? d.subtract(const Duration(days: 1)) : null,
        );
    const f = LocationType.fridge, z = LocationType.freezer, p = LocationType.pantry;
    _items['home'] = {
      for (final i in [
        it('Mléko polotučné', 'milk', 1, f, opened: true),
        it('Bílý jogurt', 'yogurt', 0, f, q: 3),
        it('Šunka nejvyšší jakosti', 'deli', -1, f),
        it('Eidam 30 %', 'cheeseHard', 12, f, type: DateType.bestBefore),
        it('Kuřecí prsa', 'poultry', 2, f, q: 500, unit: 'g'),
        it('Rajčata', 'vegetables', 5, f, q: 6),
        it('Vejce M', 'eggs', 18, f, q: 10),
        it('Máslo', 'butter', 25, f),
        it('Mražené maliny', 'frozen', 140, z),
        it('Pizza šunková', 'frozen', 60, z, q: 2),
        it('Guláš (zbytek)', 'leftovers', 80, z),
        it('Cibule', 'rootVeg', 20, p, q: 1, unit: 'kg'),
        it('Kečup', 'sauces', -3, p, type: DateType.bestBefore, opened: true),
      ])
        i.id: i,
    };
  }

  /// Current value, then a new one after every change. Changes are captured
  /// from the start, so none are lost while the listener is paused.
  Stream<T> _watch<T>(T Function() read) => Stream.multi((c) {
        c.add(read());
        final sub = _changes.stream.listen((_) => c.add(read()));
        // Don't return the cancel future: Stream.first waits for it.
        c.onCancel = () {
          sub.cancel();
        };
      });

  void _changed() => _changes.add(null);

  @override
  Stream<List<Household>> watchHouseholds(String uid) =>
      _watch(() => _households.where((h) => h.memberIds.contains(uid)).toList());

  @override
  Future<String> createHousehold(String uid, String name) async {
    final id = 'h${_seq++}';
    _households.add(Household(id: id, name: name, memberIds: [uid]));
    _items[id] = {};
    _changed();
    return id;
  }

  @override
  Future<void> leaveHousehold(String householdId, String uid) async {
    _households.removeWhere((h) => h.id == householdId);
    _changed();
  }

  @override
  Future<InviteInfo> createInvite(String householdId, String householdName, String uid) async {
    final code = 'DEMO${(1000 + _seq++).toString()}';
    return _invites[code] = InviteInfo(
        code: code, householdId: householdId, householdName: householdName,
        expiresAt: DateTime.now().add(const Duration(days: 7)));
  }

  @override
  Future<InviteInfo?> getInvite(String code) async => _invites[code.toUpperCase().trim()];

  @override
  Future<String> joinHousehold(String code, String uid) async {
    final invite = await getInvite(code);
    if (invite == null) throw StateError('invalid-invite');
    return invite.householdId;
  }

  @override
  Stream<List<PantryItem>> watchActiveItems(String householdId) => _watch(() =>
      (_items[householdId]?.values ?? const <PantryItem>[]).where((i) => i.status == ItemStatus.active).toList());

  void _log(String hid, HistoryEvent e) =>
      (_events[hid] ??= []).insert(0, HistoryEvent.fromMap('e${_seq++}', e.toMap()));

  @override
  Future<void> addItem(String householdId, PantryItem item, GlebaUser by) async {
    final id = item.id.isEmpty ? 'i${_seq++}' : item.id;
    final saved = PantryItem.fromMap(id, item.toMap()..['addedBy'] = by.uid);
    (_items[householdId] ??= {})[id] = saved;
    _log(householdId, HistoryEvent.forItem(saved, HistoryType.added, by: by.uid, byName: by.shortName));
    if (item.ean != null) await rememberProduct(householdId, item);
    _changed();
  }

  @override
  Future<void> updateItem(String householdId, PantryItem item, {HistoryType? history, GlebaUser? by}) async {
    _items[householdId]?[item.id] = item;
    if (history != null) _log(householdId, HistoryEvent.forItem(item, history, by: by?.uid, byName: by?.shortName));
    _changed();
  }

  @override
  Future<String> finishItem(String householdId, PantryItem item, ItemStatus how, GlebaUser by,
      {double? quantity}) async {
    final q = quantity ?? item.quantity;
    final remaining = item.quantity - q;
    _items[householdId]?[item.id] = remaining > 0 ? item.copyWith(quantity: remaining) : item.copyWith(status: how);
    _log(householdId, HistoryEvent.forItem(item, how == ItemStatus.discarded ? HistoryType.discarded : HistoryType.consumed,
        by: by.uid, byName: by.shortName, quantity: q));
    _changed();
    return _events[householdId]!.first.id;
  }

  @override
  Future<void> undoFinish(String householdId, PantryItem original, String eventId) async {
    _items[householdId]?[original.id] = original;
    _events[householdId]?.removeWhere((e) => e.id == eventId);
    _changed();
  }

  @override
  Future<void> restoreFromHistory(String householdId, HistoryEvent event, GlebaUser by) async {
    final item = _items[householdId]?[event.itemId];
    if (item == null) return;
    final q = event.quantity ?? 1;
    final restored = item.status == ItemStatus.active
        ? item.copyWith(quantity: item.quantity + q)
        : item.copyWith(status: ItemStatus.active, quantity: q);
    _items[householdId]![item.id] = restored;
    _log(householdId, HistoryEvent.forItem(restored, HistoryType.restored, by: by.uid, byName: by.shortName, quantity: q));
    _changed();
  }

  @override
  Stream<List<HistoryEvent>> watchHistory(String householdId, {int limit = 200}) =>
      _watch(() => (_events[householdId] ?? const []).take(limit).toList());

  @override
  Future<ProductInfo?> householdProduct(String householdId, String ean) async => _products['$householdId/$ean'];

  @override
  Future<void> rememberProduct(String householdId, PantryItem item) async {
    _products['$householdId/${item.ean}'] = ProductInfo(
      ean: item.ean!, name: item.name, brand: item.brand, categoryId: item.categoryId,
      locationType: item.locationType, source: 'household');
  }

  @override
  Future<PantryItem?> getItem(String householdId, String itemId) async => _items[householdId]?[itemId];

  @override
  Stream<List<NotificationRule>> watchNotificationRules(String uid) => _watch(() => _rules.values.toList());

  @override
  Future<void> saveNotificationRule(String uid, NotificationRule rule) async {
    _rules[rule.key] = rule;
    _changed();
  }

  @override
  Future<void> deleteNotificationRule(String uid, NotificationRule rule) async {
    _rules.remove(rule.key);
    _changed();
  }

  @override
  Stream<NotificationPrefs> watchNotificationPrefs(String uid) => _watch(() => _prefs);

  @override
  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs) async {
    _prefs = prefs;
    _changed();
  }

  @override
  Future<void> saveDevice(String uid, String deviceId, Map<String, Object?> data) async {}

  @override
  Future<void> deleteDevice(String uid, String deviceId) async {}

  @override
  Future<void> snoozeItem(String uid, PantryItem item, DateTime until) async {}

  @override
  Stream<List<ShoppingEntry>> watchShoppingList(String householdId) =>
      _watch(() => (_shopping[householdId]?.values ?? const <ShoppingEntry>[]).toList());

  @override
  Future<void> addShopping(String householdId, ShoppingEntry entry, GlebaUser by) async {
    final id = 's${_seq++}';
    (_shopping[householdId] ??= {})[id] =
        ShoppingEntry.fromMap(id, {...entry.toMap(), 'byName': by.shortName, 'createdAt': DateTime.now()});
    _changed();
  }

  @override
  Future<void> setShoppingDone(String householdId, String entryId, bool done) async {
    final e = _shopping[householdId]?[entryId];
    if (e == null) return;
    _shopping[householdId]![entryId] = ShoppingEntry.fromMap(entryId, {...e.toMap(), 'done': done, 'createdAt': e.createdAt});
    _changed();
  }

  @override
  Future<void> deleteShopping(String householdId, String entryId) async {
    _shopping[householdId]?.remove(entryId);
    _changed();
  }

  @override
  Future<void> clearBought(String householdId) async {
    _shopping[householdId]?.removeWhere((_, e) => e.done);
    _changed();
  }

  @override
  Stream<List<StockRule>> watchStockRules(String householdId) =>
      _watch(() => (_stock[householdId]?.values ?? const <StockRule>[]).toList());

  @override
  Future<void> saveStockRule(String householdId, StockRule rule) async {
    (_stock[householdId] ??= {})[rule.productKey] = rule;
    _changed();
  }

  @override
  Future<void> deleteStockRule(String householdId, String productKey) async {
    _stock[householdId]?.remove(productKey);
    _changed();
  }
}
