import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/expiry_date_parser.dart';
import 'package:gleba/domain/models.dart';

void main() {
  final now = DateTime(2026, 11, 23);
  DateTime? best(String s) => bestExpiryCandidate(s, now: now)?.date;

  test('Czech numeric formats', () {
    expect(best('Spotřebujte do: 28.11.26'), DateTime(2026, 11, 28));
    expect(best('28. 11. 2026'), DateTime(2026, 11, 28));
    expect(best('28/11/2026'), DateTime(2026, 11, 28));
  });

  test('ISO format', () => expect(best('EXP 2027-01-15'), DateTime(2027, 1, 15)));

  test('textual months CZ and EN', () {
    expect(best('BEST BEFORE 12 MAR 27'), DateTime(2027, 3, 12));
    expect(best('min. trvanlivost do 5. bře 2027'), DateTime(2027, 3, 5));
  });

  test('month/year means end of month', () => expect(best('MHD 03/2027'), DateTime(2027, 3, 31)));

  test('keyword decides date type', () {
    expect(bestExpiryCandidate('Spotřebujte do 01.12.26', now: now)!.dateType, DateType.useBy);
    expect(bestExpiryCandidate('Minimální trvanlivost do 01.12.27', now: now)!.dateType, DateType.bestBefore);
  });

  test('production date loses to expiry date', () {
    expect(best('Vyrobeno: 20.11.26  Spotřebujte do: 04.12.26'), DateTime(2026, 12, 4));
  });

  test('OCR confusions are fixed', () => expect(best('3O.11.2O26'), DateTime(2026, 11, 30)));

  test('no date', () => expect(best('Mléko polotučné 1,5 %'), isNull));
}
