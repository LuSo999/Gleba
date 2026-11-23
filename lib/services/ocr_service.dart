import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Photographs the package and reads the text on it, on the device (ML Kit,
/// free and offline). The text is then parsed by `findExpiryCandidates`.
class OcrService {
  /// ML Kit runs on Android only; the web falls back to manual entry.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Takes a photo; null when the user cancelled.
  static Future<XFile?> capture() =>
      ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 88);

  /// Reads the text on [photo] on the device (Android only).
  static Future<String> recognize(XFile photo) async {
    if (!supported) return '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(InputImage.fromFilePath(photo.path))).text;
    } finally {
      await recognizer.close();
    }
  }
}
