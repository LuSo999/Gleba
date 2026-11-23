import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/domain/shelf_life.dart';

void main() {
  test('guesses category from OFF tags and names', () {
    expect(guessCategory(tags: ['en:dairies', 'en:yogurts']).id, 'yogurt');
    expect(guessCategory(name: 'Cibule žlutá 1 kg').id, 'rootVeg');
    expect(guessCategory(name: 'Mražené jahody').id, 'frozen');
    expect(guessCategory(name: 'Žampiony').id, 'vegetables');
    expect(guessCategory(name: 'Něco divného').id, 'other');
  });

  test('suggests locations', () {
    expect(suggestLocation('frozen'), LocationType.freezer);
    expect(suggestLocation('rootVeg'), LocationType.pantry);
    expect(suggestLocation('milk'), LocationType.fridge);
  });

  final item = PantryItem(id: 'a', name: 'Mléko', categoryId: 'milk', expiryDate: DateTime(2026, 12, 10));

  test('opening shortens, never extends', () {
    expect(expiryAfterOpening(item, DateTime(2026, 11, 23)), DateTime(2026, 11, 26));
    expect(expiryAfterOpening(item, DateTime(2026, 12, 9)), DateTime(2026, 12, 10));
  });

  test('freezing extends', () => expect(expiryAfterFreezing(item, DateTime(2026, 11, 23)), DateTime(2027, 2, 21)));

  test('learned days take precedence', () {
    expect(suggestExpiry('milk', LocationType.fridge, DateTime(2026, 11, 23)), DateTime(2026, 11, 30));
    expect(suggestExpiry('milk', LocationType.fridge, DateTime(2026, 11, 23), learnedDays: 10), DateTime(2026, 12, 3));
  });
}
