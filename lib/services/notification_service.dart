import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/freshness.dart';
import '../domain/models.dart';
import '../domain/notification_rules.dart';
import '../domain/shelf_life.dart';
import '../l10n/app_localizations.dart';

/// What the user did with a notification.
class NotificationAction {
  const NotificationAction({required this.action, this.householdId, this.itemId});

  /// 'eaten', 'discarded', 'snooze' or 'open'.
  final String action;
  final String? householdId;
  final String? itemId;
}

/// Schedules expiry notifications locally on the phone (no server needed).
/// The schedule is recomputed from scratch whenever items or rules change.
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  static const _channelId = 'expiry';
  static const _maxScheduled = 60; // Android caps pending alarms per app

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  /// Local scheduling is Android-only for now (web needs FCM, see docs/plan.md).
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<NotificationAction?> init(void Function(NotificationAction) onAction) async {
    if (!supported || _ready) return null;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Prague'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onAction(_parse(r)),
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    return launch?.didNotificationLaunchApp == true && response != null ? _parse(response) : null;
  }

  NotificationAction _parse(NotificationResponse r) {
    final parts = (r.payload ?? '').split(':');
    return NotificationAction(
      action: r.actionId ?? 'open',
      householdId: parts.length == 3 && parts[0] == 'item' ? parts[1] : null,
      itemId: parts.length == 3 && parts[0] == 'item' ? parts[2] : null,
    );
  }

  AndroidNotificationDetails _details(AppLocalizations l, {bool withActions = true}) => AndroidNotificationDetails(
        _channelId,
        l.channelName,
        importance: Importance.high,
        priority: Priority.high,
        actions: withActions
            ? [
                AndroidNotificationAction('eaten', '😋 ${l.eaten}', showsUserInterface: true),
                AndroidNotificationAction('discarded', '🗑️ ${l.discarded}', showsUserInterface: true),
                AndroidNotificationAction('snooze', l.snooze, showsUserInterface: true),
              ]
            : null,
      );

  String _title(PantryItem i) => '${categoryById(i.categoryId).emoji} ${i.name}';

  String _body(AppLocalizations l, PantryItem i, DateTime at) {
    final left = daysLeft(i.expiryDate, at);
    final when = left >= 0 ? l.daysLeft(left) : l.expiredAgo(-left);
    return '${i.dateType == DateType.useBy ? l.useBy : l.bestBefore}: $when';
  }

  Future<void> reschedule({
    required List<PantryItem> items,
    required List<NotificationRule> rules,
    required NotificationPrefs prefs,
    required AppLocalizations l,
  }) async {
    if (!_ready) return;
    if (!_permissionAsked) {
      _permissionAsked = true;
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    final plan = planNotifications(items: items, rules: rules, prefs: prefs, now: DateTime.now());
    final byId = {for (final i in items) i.id: i};
    await _plugin.cancelAll();
    for (final p in plan.take(_maxScheduled)) {
      final at = tz.TZDateTime.from(p.at, tz.local);
      if (p.kind == PlannedKind.item) {
        final item = byId[p.itemIds.single]!;
        await _plugin.zonedSchedule(
          id: p.id,
          scheduledDate: at,
          title: _title(item),
          body: _body(l, item, p.at),
          payload: 'item:${item.householdId}:${item.id}',
          notificationDetails: NotificationDetails(android: _details(l)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } else {
        final names = p.itemIds.map((id) => byId[id]!.name).take(5).join(', ');
        await _plugin.zonedSchedule(
          id: p.id,
          scheduledDate: at,
          title: '🧊 ${l.digestTitle}',
          body: l.digestBody(p.itemIds.length, names),
          payload: 'digest',
          notificationDetails: NotificationDetails(android: _details(l, withActions: false)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  /// "Remind me tomorrow": the same notification again in 24 hours.
  Future<void> snooze(PantryItem item, AppLocalizations l) async {
    if (!_ready) return;
    final at = tz.TZDateTime.now(tz.local).add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: stableId('snooze-${item.id}'),
      scheduledDate: at,
      title: _title(item),
      body: _body(l, item, at),
      payload: 'item:${item.householdId}:${item.id}',
      notificationDetails: NotificationDetails(android: _details(l)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
