// PLACEHOLDER – will be overwritten by `flutterfire configure`.
// Until then the app runs in demo mode (in-memory data, no sign-in).
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase is not configured yet. Run `flutterfire configure`.');
}
