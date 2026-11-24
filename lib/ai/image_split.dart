import 'dart:math';

import 'package:image/image.dart' as img;

import 'ai_models.dart';

/// Very long receipts (screenshots of e-receipts, long paper slips) make the
/// providers fail; cut them into overlapping pieces of a sane aspect ratio.
List<AiImage> splitTallImage(AiImage image, {double maxRatio = 3, double pieceRatio = 2, double overlap = 0.08}) {
  var decoded = img.decodeImage(image.bytes);
  if (decoded == null || decoded.height <= decoded.width * maxRatio) return [image];
  // Screenshots often have transparent margins: JPEG would turn them black.
  if (decoded.hasAlpha) {
    final white = img.Image(width: decoded.width, height: decoded.height)..clear(img.ColorRgb8(255, 255, 255));
    decoded = img.compositeImage(white, decoded);
  }
  final w = decoded.width;
  final pieceH = (w * pieceRatio).round();
  final step = (pieceH * (1 - overlap)).round();
  final out = <AiImage>[];
  for (var y = 0; y < decoded.height; y += step) {
    final h = min(pieceH, decoded.height - y);
    final piece = img.copyCrop(decoded, x: 0, y: y, width: w, height: h);
    out.add(AiImage(img.encodeJpg(piece, quality: 90)));
    if (y + h >= decoded.height) break;
  }
  return out;
}
