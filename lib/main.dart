import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_state.dart';
import 'data/demo_repository.dart';
import 'data/firebase_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  var firebaseReady = false;
  try {
    // Throws while lib/firebase_options.dart is still the placeholder.
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Offline-first: reads come from the local cache, writes sync later.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not available, running in demo mode: $e');
  }

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      isDemoProvider.overrideWithValue(!firebaseReady),
      if (firebaseReady) ...[
        authServiceProvider.overrideWithValue(FirebaseAuthService(FirebaseAuth.instance)),
        repositoryProvider.overrideWithValue(FirestoreRepository(FirebaseFirestore.instance)),
      ] else ...[
        authServiceProvider.overrideWithValue(DemoAuthService()),
        repositoryProvider.overrideWithValue(DemoRepository()),
      ],
    ],
    child: const GlebaApp(),
  ));
}
