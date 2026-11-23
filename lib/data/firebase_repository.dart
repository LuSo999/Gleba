import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/history.dart';
import '../domain/meal_plan.dart';
import '../domain/models.dart';
import '../domain/notification_rules.dart';
import '../domain/shared_products.dart';
import '../domain/shopping.dart';
import 'repository.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  GlebaUser? _map(User? u) => u == null ? null : GlebaUser(uid: u.uid, email: u.email, displayName: u.displayName);

  @override
  Stream<GlebaUser?> userChanges() => _auth.authStateChanges().map(_map);

  @override
  GlebaUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()..addScope('email');
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      await _auth.signInWithProvider(provider);
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> registerWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

class FirestoreRepository implements GlebaRepository {
  FirestoreRepository(this._db);

  final FirebaseFirestore _db;

  /// Offline-first writes: Firestore applies a write to the local cache at
  /// once, but its Future only completes when the *server* confirms – without
  /// signal (a cellar, a shop) the UI would hang. So we don't wait for the
  /// server; pending writes are kept on disk and synced when back online.
  Future<void> _local(Future<Object?> write) {
    unawaited(write.then((_) {}, onError: (Object e) => debugPrint('Firestore write failed: $e')));
    return Future.value();
  }

  final _random = Random.secure();

  CollectionReference<Map<String, dynamic>> get _households => _db.collection('households');
  CollectionReference<Map<String, dynamic>> _items(String hid) => _households.doc(hid).collection('items');

  @override
  Stream<List<Household>> watchHouseholds(String uid) => _households
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => Household.fromMap(d.id, d.data())).toList()..sort((a, b) => a.name.compareTo(b.name)),
      );

  @override
  Future<String> createHousehold(String uid, String name) async {
    final doc = _households.doc();
    final batch = _db.batch()
      ..set(doc, {
        'name': name,
        'memberIds': [uid],
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'settings': {'locationsEnabled': true, 'currency': 'CZK', 'aiMode': 'off'},
      });
    for (final (i, type) in LocationType.values.take(3).indexed) {
      batch.set(doc.collection('locations').doc(type.name), {'type': type.name, 'order': i});
    }
    await _local(batch.commit());
    return doc.id;
  }

  @override
  Future<void> leaveHousehold(String householdId, String uid) => _local(
    _households.doc(householdId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
    }),
  );

  @override
  Future<InviteInfo> createInvite(String householdId, String householdName, String uid) async {
    final code = List.generate(8, (_) => inviteAlphabet[_random.nextInt(inviteAlphabet.length)]).join();
    final expiresAt = DateTime.now().add(const Duration(days: 7));
    await _db.collection('invites').doc(code).set({
      'householdId': householdId,
      'householdName': householdName,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'maxUses': 10,
      'uses': 0,
    });
    return InviteInfo(code: code, householdId: householdId, householdName: householdName, expiresAt: expiresAt);
  }

  @override
  Future<InviteInfo?> getInvite(String code) async {
    final snap = await _db.collection('invites').doc(code.toUpperCase().trim()).get();
    final d = snap.data();
    if (d == null) return null;
    final expires = (d['expiresAt'] as Timestamp).toDate();
    if (expires.isBefore(DateTime.now()) || (d['uses'] as num) >= (d['maxUses'] as num)) return null;
    return InviteInfo(
      code: snap.id,
      householdId: d['householdId'] as String,
      householdName: d['householdName'] as String,
      expiresAt: expires,
    );
  }

  @override
  Future<String> joinHousehold(String code, String uid) async {
    final invite = await getInvite(code);
    if (invite == null) throw StateError('invalid-invite');
    // Security rules verify the invite in the same batch (see firestore.rules).
    // Joining needs the server's yes, so this one does wait (needs internet).
    await (_db.batch()
          ..update(_db.collection('invites').doc(invite.code), {'uses': FieldValue.increment(1)})
          ..update(_households.doc(invite.householdId), {
            'memberIds': FieldValue.arrayUnion([uid]),
            'lastJoinCode': invite.code,
          }))
        .commit()
        .timeout(const Duration(seconds: 20));
    return invite.householdId;
  }

  @override
  Stream<List<PantryItem>> watchActiveItems(String householdId) =>
      _items(householdId)
          .where('status', isEqualTo: ItemStatus.active.name)
          .snapshots()
          .map((s) => s.docs.map((d) => PantryItem.fromMap(d.id, d.data())).toList());

  Map<String, Object?> _toFirestore(PantryItem item) =>
      item.toMap().map((k, v) => MapEntry(k, v is DateTime ? Timestamp.fromDate(v) : v));

  CollectionReference<Map<String, dynamic>> _events(String hid) => _households.doc(hid).collection('events');

  Map<String, Object?> _eventData(HistoryEvent e) => e.toMap()..['at'] = FieldValue.serverTimestamp();

  @override
  Future<void> addItem(String householdId, PantryItem item, GlebaUser by) async {
    final doc = item.id.isEmpty ? _items(householdId).doc() : _items(householdId).doc(item.id);
    final data = _toFirestore(item)
      ..['addedBy'] = by.uid
      ..['addedAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    final saved = PantryItem.fromMap(doc.id, item.toMap());
    await _local(
      (_db.batch()
            ..set(doc, data)
            ..set(
              _events(householdId).doc(),
              _eventData(HistoryEvent.forItem(saved, HistoryType.added, by: by.uid, byName: by.shortName)),
            ))
          .commit(),
    );
    if (item.ean != null) await rememberProduct(householdId, item);
  }

  @override
  Future<void> updateItem(String householdId, PantryItem item, {HistoryType? history, GlebaUser? by}) async {
    final batch = _db.batch()
      ..update(_items(householdId).doc(item.id), _toFirestore(item)..['updatedAt'] = FieldValue.serverTimestamp());
    if (history != null) {
      batch.set(
        _events(householdId).doc(),
        _eventData(HistoryEvent.forItem(item, history, by: by?.uid, byName: by?.shortName)),
      );
    }
    await _local(batch.commit());
  }

  @override
  Future<String> finishItem(
    String householdId,
    PantryItem item,
    ItemStatus how,
    GlebaUser by, {
    double? quantity,
  }) async {
    final q = quantity ?? item.quantity;
    final remaining = item.quantity - q;
    final event = _events(householdId).doc();
    await _local(
      (_db.batch()
            ..update(_items(householdId).doc(item.id), {
              if (remaining > 0) 'quantity': remaining else 'status': how.name,
              'updatedAt': FieldValue.serverTimestamp(),
            })
            ..set(
              event,
              _eventData(
                HistoryEvent.forItem(
                  item,
                  how == ItemStatus.discarded ? HistoryType.discarded : HistoryType.consumed,
                  by: by.uid,
                  byName: by.shortName,
                  quantity: q,
                ),
              )..['daysLeft'] = dateOnly(item.expiryDate).difference(dateOnly(DateTime.now())).inDays,
            ))
          .commit(),
    );
    return event.id;
  }

  @override
  Future<void> undoFinish(String householdId, PantryItem original, String eventId) => _local(
    (_db.batch()
          ..update(_items(householdId).doc(original.id), {
            'quantity': original.quantity,
            'status': original.status.name,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          ..delete(_events(householdId).doc(eventId)))
        .commit(),
  );

  @override
  Future<void> restoreFromHistory(String householdId, HistoryEvent event, GlebaUser by) async {
    final ref = _items(householdId).doc(event.itemId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final item = PantryItem.fromMap(snap.id, snap.data()!);
    final q = event.quantity ?? 1;
    final restored = item.status == ItemStatus.active
        ? item.copyWith(quantity: item.quantity + q)
        : item.copyWith(status: ItemStatus.active, quantity: q);
    await _local(
      (_db.batch()
            ..update(ref, {
              'status': restored.status.name,
              'quantity': restored.quantity,
              'updatedAt': FieldValue.serverTimestamp(),
            })
            ..set(
              _events(householdId).doc(),
              _eventData(
                HistoryEvent.forItem(restored, HistoryType.restored, by: by.uid, byName: by.shortName, quantity: q),
              ),
            ))
          .commit(),
    );
  }

  @override
  Future<List<HistoryEvent>> fetchEvents(String householdId, {DateTime? since}) async {
    Query<Map<String, dynamic>> q = _events(householdId);
    if (since != null) q = q.where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    final snap = await q.get();
    return snap.docs.map((d) => HistoryEvent.fromMap(d.id, d.data())).toList();
  }

  @override
  Stream<List<HistoryEvent>> watchHistory(String householdId, {int limit = 200}) =>
      _events(householdId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map((d) => HistoryEvent.fromMap(d.id, d.data())).toList());

  @override
  Future<ProductInfo?> householdProduct(String householdId, String ean) async {
    final d = (await _households.doc(householdId).collection('products').doc(ean).get()).data();
    if (d == null) return null;
    return ProductInfo(
      ean: ean,
      name: d['name'] as String,
      brand: d['brand'] as String?,
      imageUrl: d['imageUrl'] as String?,
      categoryId: d['categoryId'] as String?,
      locationType: LocationType.values.where((l) => l.name == d['locationType']).firstOrNull,
      shelfLifeDays: (d['shelfLifeDays'] as num?)?.toInt(),
      source: 'household',
      nutrition: Nutrition.fromMap(d['nutrition']),
    );
  }

  @override
  Future<ProductInfo?> sharedProduct(String ean) async {
    if (!isShareableEan(ean)) return null;
    final d = (await _db.collection('products').doc(ean).get()).data();
    if (d == null || (d['name'] as String?)?.isNotEmpty != true) return null;
    final stats = ShelfLifeStats.fromMap(d['shelfLifeStats']);
    return ProductInfo(
      ean: ean,
      name: d['name'] as String,
      brand: d['brand'] as String?,
      imageUrl: d['imageUrl'] as String?,
      categoryId: d['categoryId'] as String?,
      shelfLifeDays: stats.suggestedDays,
      source: 'gleba',
    );
  }

  @override
  Future<void> contributeProduct(PantryItem item, {int? shelfLifeDays}) async {
    final ean = item.ean;
    if (!isShareableEan(ean)) return;
    final ref = _db.collection('products').doc(ean);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          tx.set(ref, {
            'name': item.name,
            'brand': item.brand,
            'categoryId': item.categoryId,
            'imageUrl': item.imageUrl,
            'source': 'gleba',
            'shelfLifeStats':
                (shelfLifeDays == null ? const ShelfLifeStats() : const ShelfLifeStats().add(shelfLifeDays)).toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else if (shelfLifeDays != null) {
          final stats = ShelfLifeStats.fromMap(snap.data()?['shelfLifeStats']).add(shelfLifeDays);
          tx.update(ref, {'shelfLifeStats': stats.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
        }
      });
    } catch (e) {
      // Sharing is best-effort (e.g. offline); the household copy is already saved.
      debugPrint('contributeProduct failed: $e');
    }
  }

  @override
  Future<void> rememberProduct(String householdId, PantryItem item) => _local(
    _households.doc(householdId).collection('products').doc(item.ean).set({
      'name': item.name,
      'brand': item.brand,
      'imageUrl': item.imageUrl,
      'categoryId': item.categoryId,
      'locationType': item.locationType?.name,
      'shelfLifeDays': dateOnly(item.expiryDate).difference(dateOnly(DateTime.now())).inDays,
      'lastPrice': item.price,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)),
  );

  @override
  Future<PantryItem?> getItem(String householdId, String itemId) async {
    final d = await _items(householdId).doc(itemId).get();
    return d.exists ? PantryItem.fromMap(d.id, d.data()!) : null;
  }

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);

  @override
  Stream<List<NotificationRule>> watchNotificationRules(String uid) =>
      _user(uid)
          .collection('notificationRules')
          .snapshots()
          .map((s) => s.docs.map((d) => NotificationRule.fromMap(d.data())).toList());

  @override
  Future<void> saveNotificationRule(String uid, NotificationRule rule) =>
      _local(_user(uid).collection('notificationRules').doc(rule.key).set(rule.toMap()));

  @override
  Future<void> deleteNotificationRule(String uid, NotificationRule rule) =>
      _local(_user(uid).collection('notificationRules').doc(rule.key).delete());

  @override
  Stream<NotificationPrefs> watchNotificationPrefs(String uid) =>
      _user(uid)
          .collection('preferences')
          .doc('notifications')
          .snapshots()
          .map((d) => NotificationPrefs.fromMap(d.data()));

  @override
  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs) =>
      _local(_user(uid).collection('preferences').doc('notifications').set(prefs.toMap()));

  @override
  Future<void> saveDevice(String uid, String deviceId, Map<String, Object?> data) =>
      _local(_user(uid).collection('devices').doc(deviceId).set({...data, 'updatedAt': FieldValue.serverTimestamp()}));

  @override
  Future<void> deleteDevice(String uid, String deviceId) =>
      _local(_user(uid).collection('devices').doc(deviceId).delete());

  @override
  Future<void> snoozeItem(String uid, PantryItem item, DateTime until) => _local(
    _user(uid)
        .collection('snoozes')
        .doc(item.id)
        .set({'until': Timestamp.fromDate(until), 'householdId': item.householdId}),
  );

  CollectionReference<Map<String, dynamic>> _shopping(String hid) => _households.doc(hid).collection('shoppingList');
  CollectionReference<Map<String, dynamic>> _stock(String hid) => _households.doc(hid).collection('stockRules');

  /// Firestore document ids can't contain "/".
  static String _ruleId(String productKey) => productKey.replaceAll('/', '_');

  @override
  Stream<List<ShoppingEntry>> watchShoppingList(String householdId) =>
      _shopping(householdId).snapshots().map((s) => s.docs.map((d) => ShoppingEntry.fromMap(d.id, d.data())).toList());

  @override
  Future<void> addShopping(String householdId, ShoppingEntry entry, GlebaUser by) => _local(
    _shopping(householdId)
        .add({...entry.toMap(), 'byName': by.shortName, 'by': by.uid, 'createdAt': FieldValue.serverTimestamp()}),
  );

  @override
  Future<void> setShoppingDone(String householdId, String entryId, bool done) =>
      _local(_shopping(householdId).doc(entryId).update({'done': done}));

  @override
  Future<void> deleteShopping(String householdId, String entryId) =>
      _local(_shopping(householdId).doc(entryId).delete());

  @override
  Future<void> clearBought(String householdId) async {
    final done = await _shopping(householdId).where('done', isEqualTo: true).get();
    final batch = _db.batch();
    for (final d in done.docs) {
      batch.delete(d.reference);
    }
    await _local(batch.commit());
  }

  @override
  Stream<List<StockRule>> watchStockRules(String householdId) =>
      _stock(householdId).snapshots().map((s) => s.docs.map((d) => StockRule.fromMap(d.data())).toList());

  @override
  Future<void> saveStockRule(String householdId, StockRule rule) =>
      _local(_stock(householdId).doc(_ruleId(rule.productKey)).set(rule.toMap()));

  @override
  Future<void> deleteStockRule(String householdId, String productKey) =>
      _local(_stock(householdId).doc(_ruleId(productKey)).delete());

  CollectionReference<Map<String, dynamic>> _meals(String hid) => _households.doc(hid).collection('meals');

  @override
  Stream<List<Meal>> watchMeals(String householdId, String from, String to) => _meals(householdId)
      .where('date', isGreaterThanOrEqualTo: from)
      .where('date', isLessThanOrEqualTo: to)
      .snapshots()
      .map((s) => s.docs.map((d) => Meal.fromMap(d.id, d.data())).toList());

  @override
  Future<void> saveMeal(String householdId, Meal meal, GlebaUser by) {
    final ref = meal.id.isEmpty ? _meals(householdId).doc() : _meals(householdId).doc(meal.id);
    return _local(ref.set({...meal.toMap(), 'byName': meal.byName ?? by.shortName, 'updatedAt': FieldValue.serverTimestamp()}));
  }

  @override
  Future<void> deleteMeal(String householdId, String mealId) => _local(_meals(householdId).doc(mealId).delete());
}
