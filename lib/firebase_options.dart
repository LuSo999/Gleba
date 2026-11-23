// Firebase configuration for project `gleba-e9a60`.
// Can be regenerated with `flutterfire configure --project=gleba-e9a60`.
//
// TODO: fill in apiKey and appId for each platform (Firebase console →
// Project settings → Your apps). Until then the app runs in demo mode.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const _projectId = 'gleba-e9a60';
  static const _senderId = '420766037857'; // project number

  static FirebaseOptions get currentPlatform {
    final options = kIsWeb
        ? web
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => android,
            _ => throw UnsupportedError('Gleba supports Android and web only.'),
          };
    if (options.apiKey.isEmpty || options.appId.isEmpty) {
      throw UnsupportedError('Firebase apiKey/appId not filled in yet (lib/firebase_options.dart).');
    }
    return options;
  }

  static const web = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: _senderId,
    projectId: _projectId,
    authDomain: '$_projectId.firebaseapp.com',
    storageBucket: '$_projectId.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: _senderId,
    projectId: _projectId,
    storageBucket: '$_projectId.firebasestorage.app',
  );
}
