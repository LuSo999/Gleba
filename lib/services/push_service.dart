import 'dart:async';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'notification_service.dart';

/// Registers this phone with the server so it can receive push notifications,
/// and shows messages that arrive while the app is open.
class PushService {
  PushService._();

  static final instance = PushService._();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  String? _registeredUid;

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('deviceId');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('deviceId', id);
    }
    return id;
  }

  Future<void> register(GlebaRepository repo, GlebaUser user, String locale) async {
    if (!NotificationService.supported || _registeredUid == user.uid) return;
    _registeredUid = user.uid;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    await NotificationService.instance.requestPermission();
    final deviceId = await _deviceId();
    String tz;
    try {
      tz = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      tz = 'Europe/Prague';
    }
    Future<void> save(String? token) async {
      if (token == null) return;
      await repo.saveDevice(user.uid, deviceId, {'token': token, 'tz': tz, 'locale': locale, 'platform': 'android'});
    }

    // onRegistered fires with the token now and again whenever it changes.
    await _tokenSub?.cancel();
    _tokenSub = messaging.onRegistered.listen(save);
    await messaging.register();
    await _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen((m) => NotificationService.instance.show(m.data));
  }

  /// Call before signing out, so the phone stops getting this user's notifications.
  Future<void> unregister(GlebaRepository repo, GlebaUser user) async {
    if (!NotificationService.supported) return;
    _registeredUid = null;
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    try {
      await repo.deleteDevice(user.uid, await _deviceId());
    } catch (_) {}
  }
}

/// Runs in a separate isolate when a message arrives and the app is closed.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await NotificationService.instance.show(message.data);
}
