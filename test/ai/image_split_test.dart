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

  test('mime is sniffed from the bytes; transparent margins become white', () {
    final png = File('test_ai/fixtures/receipt_short.png').readAsBytesSync();
    expect(sniffImageMime(png), 'image/png');
    expect(sniffImageMime(File('test_ai/fixtures/receipt_long.jpg').readAsBytesSync()), 'image/jpeg');
    final tall = img.Image(width: 100, height: 500, numChannels: 4); // fully transparent
    final pieces = splitTallImage(AiImage.detect(img.encodePng(tall)));
    final p = img.decodeImage(pieces.first.bytes)!;
    expect(p.getPixel(5, 5).r, greaterThan(240));
  });
}
