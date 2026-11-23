import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/gs1_parser.dart';

void main() {
  final now = DateTime(2026, 11, 23);

  test('validates EAN-13 check digit', () {
    expect(isValidGtin('8594001021499'), isTrue);
    expect(isValidGtin('8594001021490'), isFalse);
    expect(isValidGtin('96385074'), isTrue); // EAN-8
  });

  test('plain EAN-13 and UPC-A', () {
    expect(parseBarcode('8594001021499').gtin, '8594001021499');
    expect(parseBarcode('036000291452').gtin, '0036000291452');
  });

  test('GS1 element string with FNC1 separators', () {
    final d = parseBarcode('0108594001021499172603121012AB$gs1GroupSeparator' '3103001250', now: now);
    expect(d.gtin, '8594001021499');
    expect(d.useBy, DateTime(2026, 3, 12));
    expect(d.batch, '12AB');
    expect(d.netWeightKg, 1.25);
  });

  test('symbology identifier prefix is ignored', () {
    expect(parseBarcode(']d2010859400102149915270100', now: now).bestBefore, DateTime(2027, 1, 31));
  });

  test('human readable form and day 00 = end of month', () {
    final d = parseBarcode('(01)08594001021499(15)270200', now: now);
    expect(d.bestBefore, DateTime(2027, 2, 28));
  });

  test('GS1 Digital Link', () {
    final d = parseBarcode('https://id.gs1.org/01/08594001021499/10/LOT7?17=261205', now: now);
    expect(d.gtin, '8594001021499');
    expect(d.useBy, DateTime(2026, 12, 5));
    expect(d.batch, 'LOT7');
  });

  test('in-store codes are detected', () {
    expect(parseBarcode('2912345000004').isInStoreCode, isTrue);
    expect(parseBarcode('8594001021499').isInStoreCode, isFalse);
  });

  test('invalid date is rejected', () {
    expect(parseGs1Date('261332', now: now), isNull);
    expect(parseGs1Date('260230', now: now), isNull);
  });
}
