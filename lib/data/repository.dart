import '../domain/models.dart';
import '../domain/notification_rules.dart';

/// Signed-in user as the app sees it (independent of Firebase).
class GlebaUser {
  const GlebaUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}

abstract class AuthService {
  Stream<GlebaUser?> userChanges();
  GlebaUser? get currentUser;
  Future<void> signInWithGoogle();
  Future<void> signInWithEmail(String email, String password);
  Future<void> registerWithEmail(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

class InviteInfo {
  const InviteInfo({required this.code, required this.householdId, required this.householdName, required this.expiresAt});

  final String code;
  final String householdId;
  final String householdName;
  final DateTime expiresAt;
}

/// Everything the UI needs from storage. Implemented by Firestore and by an
/// in-memory demo used when Firebase isn't configured yet.
abstract class GlebaRepository {
  Stream<List<Household>> watchHouseholds(String uid);
  Future<String> createHousehold(String uid, String name);
  Future<void> leaveHousehold(String householdId, String uid);

  Future<InviteInfo> createInvite(String householdId, String householdName, String uid);
  Future<InviteInfo?> getInvite(String code);

  /// Returns the joined household id.
  Future<String> joinHousehold(String code, String uid);

  Stream<List<PantryItem>> watchActiveItems(String householdId);
  Future<void> addItem(String householdId, PantryItem item, String uid);
  Future<void> updateItem(String householdId, PantryItem item);

  /// Marks [quantity] (default: everything) of an item as eaten or thrown away
  /// and records an event for statistics.
  Future<void> finishItem(String householdId, PantryItem item, ItemStatus how, String uid, {double? quantity});

  /// Product details this household already entered for [ean], if any.
  Future<ProductInfo?> householdProduct(String householdId, String ean);
  Future<void> rememberProduct(String householdId, PantryItem item);

  Future<PantryItem?> getItem(String householdId, String itemId);

  // ---- Per-user notification settings ----
  Stream<List<NotificationRule>> watchNotificationRules(String uid);
  Future<void> saveNotificationRule(String uid, NotificationRule rule);
  Future<void> deleteNotificationRule(String uid, NotificationRule rule);
  Stream<NotificationPrefs> watchNotificationPrefs(String uid);
  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs);
}

/// Invite codes: 8 chars, no look-alike characters (0/O, 1/I/L).
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
