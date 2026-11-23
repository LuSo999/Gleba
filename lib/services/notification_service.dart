import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/notification_rules.dart' show stableId;

/// What the user did with a notification.
class NotificationAction {
  const NotificationAction({required this.action, this.householdId, this.itemId});

  /// 'eaten', 'discarded', 'snooze' or 'open'.
  final String action;
  final String? householdId;
  final String? itemId;
}

/// Shows the push notifications sent by the server (functions/src/index.ts)
/// with action buttons. Also usable from the background isolate.
class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  static const _channelId = 'expiry';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Push notifications are Android-only (the user chose phone only).
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Minimal init for displaying notifications (background isolate too).
  Future<void> initDisplay({void Function(NotificationAction)? onAction}) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: onAction == null ? null : (r) => onAction(_parse(r)),
    );
    _ready = true;
  }

  /// Foreground init; returns the action that launched the app, if any.
  Future<NotificationAction?> init(void Function(NotificationAction) onAction) async {
    if (!supported) return null;
    await initDisplay(onAction: onAction);
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    return launch?.didNotificationLaunchApp == true && response != null ? _parse(response) : null;
  }

  Future<void> requestPermission() async => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  NotificationAction _parse(NotificationResponse r) {
    final parts = (r.payload ?? '').split(':');
    final isItem = parts.length == 3 && parts[0] == 'item';
    return NotificationAction(
      action: r.actionId ?? 'open',
      householdId: isItem ? parts[1] : null,
      itemId: isItem ? parts[2] : null,
    );
  }

  /// Displays a data message from the server:
  /// {kind, title, body, tag, householdId, itemId}.
  Future<void> show(Map<String, dynamic> data) async {
    await initDisplay();
    final kind = data['kind'] as String? ?? '';
    final itemId = data['itemId'] as String? ?? '';
    final hid = data['householdId'] as String? ?? '';
    final cs = PlatformDispatcher.instance.locale.languageCode == 'cs';
    final withActions = itemId.isNotEmpty && const {'soon', 'expired', 'snooze'}.contains(kind);
    final details = AndroidNotificationDetails(
      _channelId,
      cs ? 'Blížící se datum spotřeby' : 'Upcoming expiry dates',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: const BigTextStyleInformation(''),
      actions: withActions
          ? [
              AndroidNotificationAction('eaten', cs ? '😋 Snězeno' : '😋 Eaten', showsUserInterface: true),
              AndroidNotificationAction('discarded', cs ? '🗑️ Vyhozeno' : '🗑️ Thrown away', showsUserInterface: true),
              AndroidNotificationAction('snooze', cs ? 'Zítra' : 'Tomorrow', showsUserInterface: true),
            ]
          : null,
    );
    await _plugin.show(
      id: stableId(data['tag'] as String? ?? '$kind$itemId'),
      title: data['title'] as String?,
      body: data['body'] as String?,
      payload: withActions ? 'item:$hid:$itemId' : kind,
      notificationDetails: NotificationDetails(android: details),
    );
  }
}
