import '../domain/history.dart';
import '../domain/meal_plan.dart';
import '../domain/models.dart';
import '../domain/notification_rules.dart';
import '../domain/shopping.dart';

/// Signed-in user as the app sees it (independent of Firebase).
class GlebaUser {
  const GlebaUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;

  /// Short name shown in the household history.
  String get shortName => displayName ?? email?.split('@').first ?? '';
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
  Future<void> addItem(String householdId, PantryItem item, GlebaUser by);

  /// Saves a change; when [history] is given it is also logged.
  Future<void> updateItem(String householdId, PantryItem item, {HistoryType? history, GlebaUser? by});

  /// Marks [quantity] (default: everything) of an item as eaten or thrown away
  /// and records a history event. Returns the event id (needed for undo).
  Future<String> finishItem(String householdId, PantryItem item, ItemStatus how, GlebaUser by, {double? quantity});

  /// Undo right after [finishItem]: puts the item back exactly as it was and
  /// removes the history event, so statistics stay correct.
  Future<void> undoFinish(String householdId, PantryItem original, String eventId);

  /// Undo from the history later on: returns the eaten / thrown away amount to
  /// the fridge and logs a "restored" event.
  Future<void> restoreFromHistory(String householdId, HistoryEvent event, GlebaUser by);

  Stream<List<HistoryEvent>> watchHistory(String householdId, {int limit = 200});

  /// All history since [since] (null = everything), for statistics.
  Future<List<HistoryEvent>> fetchEvents(String householdId, {DateTime? since});

  /// Product details this household already entered for [ean], if any.
  Future<ProductInfo?> householdProduct(String householdId, String ean);
  Future<void> rememberProduct(String householdId, PantryItem item);

  /// Gleba's shared product database (all users), see domain/shared_products.dart.
  Future<ProductInfo?> sharedProduct(String ean);

  /// Adds the product to the shared database, or – when it's already there –
  /// adds [shelfLifeDays] (only for dates read from the package) to its average.
  Future<void> contributeProduct(PantryItem item, {int? shelfLifeDays});

  Future<PantryItem?> getItem(String householdId, String itemId);

  // ---- Per-user notification settings ----
  Stream<List<NotificationRule>> watchNotificationRules(String uid);
  Future<void> saveNotificationRule(String uid, NotificationRule rule);
  Future<void> deleteNotificationRule(String uid, NotificationRule rule);
  Stream<NotificationPrefs> watchNotificationPrefs(String uid);
  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs);

  /// Registers a phone for push notifications (FCM token, time zone, language).
  Future<void> saveDevice(String uid, String deviceId, Map<String, Object?> data);
  Future<void> deleteDevice(String uid, String deviceId);

  /// "Remind me tomorrow" – the server skips the item until [until].
  Future<void> snoozeItem(String uid, PantryItem item, DateTime until);

  // ---- Shopping list & stock rules (shared by the household) ----
  Stream<List<ShoppingEntry>> watchShoppingList(String householdId);
  Future<void> addShopping(String householdId, ShoppingEntry entry, GlebaUser by);
  Future<void> setShoppingDone(String householdId, String entryId, bool done);
  Future<void> deleteShopping(String householdId, String entryId);
  Future<void> clearBought(String householdId);
  Stream<List<StockRule>> watchStockRules(String householdId);
  Future<void> saveStockRule(String householdId, StockRule rule);
  Future<void> deleteStockRule(String householdId, String productKey);

  // ---- Meal plan (shared by the household) ----
  /// Meals with from <= date <= to (inclusive day keys "YYYY-MM-DD").
  Stream<List<Meal>> watchMeals(String householdId, String from, String to);
  Future<void> saveMeal(String householdId, Meal meal, GlebaUser by);
  Future<void> deleteMeal(String householdId, String mealId);
}

/// Invite codes: 8 chars, no look-alike characters (0/O, 1/I/L).
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
