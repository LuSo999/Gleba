import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/image_split.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a long receipt is cut into overlapping pieces, a normal photo is not', () {
    final long = AiImage(File('test_ai/fixtures/receipt_long.jpg').readAsBytesSync());
    final pieces = splitTallImage(long);
    expect(pieces.length, greaterThan(2));
    final heights = [for (final p in pieces) img.decodeImage(p.bytes)!.height];
    expect(heights.reduce((a, b) => a + b), greaterThan(2375)); // overlap
    for (final p in pieces) {
      final d = img.decodeImage(p.bytes)!;
      expect(d.height / d.width, lessThanOrEqualTo(2.01));
    }
    final short = AiImage(File('test_ai/fixtures/receipt_short.png').readAsBytesSync());
    expect(splitTallImage(short), hasLength(1));
  });
}
