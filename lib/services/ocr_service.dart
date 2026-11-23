import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Photographs the package and reads the text on it, on the device (ML Kit,
/// free and offline). The text is then parsed by `findExpiryCandidates`.
class OcrService {
  /// ML Kit runs on Android only; the web falls back to manual entry.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Returns the recognised text, or null when the user cancelled.
  static Future<String?> captureText() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 90);
    if (photo == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
