import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/notification_rules.dart';
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
  final _random = Random.secure();

  CollectionReference<Map<String, dynamic>> get _households => _db.collection('households');
  CollectionReference<Map<String, dynamic>> _items(String hid) => _households.doc(hid).collection('items');

  @override
  Stream<List<Household>> watchHouseholds(String uid) => _households
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map((d) => Household.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

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
    await batch.commit();
    return doc.id;
  }

  @override
  Future<void> leaveHousehold(String householdId, String uid) =>
      _households.doc(householdId).update({'memberIds': FieldValue.arrayRemove([uid])});

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
        code: snap.id, householdId: d['householdId'] as String, householdName: d['householdName'] as String,
        expiresAt: expires);
  }

  @override
  Future<String> joinHousehold(String code, String uid) async {
    final invite = await getInvite(code);
    if (invite == null) throw StateError('invalid-invite');
    // Security rules verify the invite in the same batch (see firestore.rules).
    await (_db.batch()
          ..update(_db.collection('invites').doc(invite.code), {'uses': FieldValue.increment(1)})
          ..update(_households.doc(invite.householdId), {
            'memberIds': FieldValue.arrayUnion([uid]),
            'lastJoinCode': invite.code,
          }))
        .commit();
    return invite.householdId;
  }

  @override
  Stream<List<PantryItem>> watchActiveItems(String householdId) => _items(householdId)
      .where('status', isEqualTo: ItemStatus.active.name)
      .snapshots()
      .map((s) => s.docs.map((d) => PantryItem.fromMap(d.id, d.data())).toList());

  Map<String, Object?> _toFirestore(PantryItem item) =>
      item.toMap().map((k, v) => MapEntry(k, v is DateTime ? Timestamp.fromDate(v) : v));

  @override
  Future<void> addItem(String householdId, PantryItem item, String uid) async {
    final doc = item.id.isEmpty ? _items(householdId).doc() : _items(householdId).doc(item.id);
    final data = _toFirestore(item)
      ..['addedBy'] = uid
      ..['addedAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await (_db.batch()
          ..set(doc, data)
          ..set(_households.doc(householdId).collection('events').doc(), {
            'itemId': doc.id,
            'type': 'added',
            'quantity': item.quantity,
            'categoryId': item.categoryId,
            'price': item.price,
            'by': uid,
            'at': FieldValue.serverTimestamp(),
          }))
        .commit();
    if (item.ean != null) await rememberProduct(householdId, item);
  }

  @override
  Future<void> updateItem(String householdId, PantryItem item) =>
      _items(householdId).doc(item.id).update(_toFirestore(item)..['updatedAt'] = FieldValue.serverTimestamp());

  @override
  Future<void> finishItem(String householdId, PantryItem item, ItemStatus how, String uid, {double? quantity}) async {
    final q = quantity ?? item.quantity;
    final remaining = item.quantity - q;
    final ref = _items(householdId).doc(item.id);
    await (_db.batch()
          ..update(ref, {
            if (remaining > 0) 'quantity': remaining else 'status': how.name,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          ..set(_households.doc(householdId).collection('events').doc(), {
            'itemId': item.id,
            'type': how == ItemStatus.discarded ? 'discarded' : 'consumed',
            'quantity': q,
            'categoryId': item.categoryId,
            'price': item.price == null ? null : item.price! * q / item.quantity,
            'daysLeft': item.expiryDate.difference(DateTime.now()).inDays,
            'by': uid,
            'at': FieldValue.serverTimestamp(),
          }))
        .commit();
  }

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
    );
  }

  @override
  Future<void> rememberProduct(String householdId, PantryItem item) =>
      _households.doc(householdId).collection('products').doc(item.ean).set({
        'name': item.name,
        'brand': item.brand,
        'imageUrl': item.imageUrl,
        'categoryId': item.categoryId,
        'locationType': item.locationType?.name,
        'shelfLifeDays': dateOnly(item.expiryDate).difference(dateOnly(DateTime.now())).inDays,
        'lastPrice': item.price,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<PantryItem?> getItem(String householdId, String itemId) async {
    final d = await _items(householdId).doc(itemId).get();
    return d.exists ? PantryItem.fromMap(d.id, d.data()!) : null;
  }

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);

  @override
  Stream<List<NotificationRule>> watchNotificationRules(String uid) => _user(uid)
      .collection('notificationRules')
      .snapshots()
      .map((s) => s.docs.map((d) => NotificationRule.fromMap(d.data())).toList());

  @override
  Future<void> saveNotificationRule(String uid, NotificationRule rule) =>
      _user(uid).collection('notificationRules').doc(rule.key).set(rule.toMap());

  @override
  Future<void> deleteNotificationRule(String uid, NotificationRule rule) =>
      _user(uid).collection('notificationRules').doc(rule.key).delete();

  @override
  Stream<NotificationPrefs> watchNotificationPrefs(String uid) => _user(uid)
      .collection('preferences')
      .doc('notifications')
      .snapshots()
      .map((d) => NotificationPrefs.fromMap(d.data()));

  @override
  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs) =>
      _user(uid).collection('preferences').doc('notifications').set(prefs.toMap());
}
