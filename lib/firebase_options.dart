// Firebase configuration for project `gleba-e9a60`.
// Can be regenerated with `flutterfire configure --project=gleba-e9a60`.
// These values are public identifiers, not secrets – access is controlled by
// firestore.rules.
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
    apiKey: 'AIzaSyBuEdYFNwTndBDgy5QmAahn7P7Te-Bdils',
    appId: '1:420766037857:web:15c92639a86269a1997720',
    measurementId: 'G-71SDBHZP9N',
    messagingSenderId: _senderId,
    projectId: _projectId,
    authDomain: '$_projectId.firebaseapp.com',
    storageBucket: '$_projectId.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDBSo4-HKYcLW5kP9m6fnLvEvV-EvV5g7w',
    appId: '1:420766037857:android:f82bddc38447fea7997720',
    messagingSenderId: _senderId,
    projectId: _projectId,
    storageBucket: '$_projectId.firebasestorage.app',
  );
}
