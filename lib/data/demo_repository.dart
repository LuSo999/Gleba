import 'dart:async';

import '../domain/models.dart';
import '../domain/notification_rules.dart';
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

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

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

  @override
  Future<void> addItem(String householdId, PantryItem item, String uid) async {
    final id = item.id.isEmpty ? 'i${_seq++}' : item.id;
    (_items[householdId] ??= {})[id] = PantryItem.fromMap(id, item.toMap()..['addedBy'] = uid);
    if (item.ean != null) await rememberProduct(householdId, item);
    _changed();
  }

  @override
  Future<void> updateItem(String householdId, PantryItem item) async {
    _items[householdId]?[item.id] = item;
    _changed();
  }

  @override
  Future<void> finishItem(String householdId, PantryItem item, ItemStatus how, String uid, {double? quantity}) async {
    final remaining = item.quantity - (quantity ?? item.quantity);
    _items[householdId]?[item.id] = remaining > 0 ? item.copyWith(quantity: remaining) : item.copyWith(status: how);
    _changed();
  }

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
}
