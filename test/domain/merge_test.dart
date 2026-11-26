import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/data/demo_repository.dart';
import 'package:gleba/data/repository.dart';
import 'package:gleba/domain/merge.dart';
import 'package:gleba/domain/models.dart';

PantryItem it(String id, String name, DateTime d, {double q = 1, double? price, LocationType loc = LocationType.fridge}) =>
    PantryItem(id: id, name: name, categoryId: 'yogurt', expiryDate: d, quantity: q, price: price, locationType: loc);

void main() {
  final d1 = DateTime(2026, 12, 1), d2 = DateTime(2026, 12, 5);

  test('same name + same date = one group; another date or place is not', () {
    final groups = duplicateGroups([
      it('a', 'Bílý jogurt', d1),
      it('b', 'bílý  jogurt', d1, q: 2),
      it('c', 'Bílý jogurt', d2),
      it('d', 'Bílý jogurt', d1, loc: LocationType.freezer),
    ]);
    expect(groups.single.map((i) => i.id), ['a', 'b']);
    final m = mergedItem(groups.single.first, groups.single.sublist(1));
    expect(m.quantity, 3);
  });

  test('prices add up; none stays none', () {
    expect(mergedItem(it('a', 'X', d1, price: 10), [it('b', 'X', d1, price: 5)]).price, 15);
    expect(mergedItem(it('a', 'X', d1), [it('b', 'X', d1)]).price, isNull);
  });

  test('same names are pulled together where the most urgent one is', () {
    final sorted = [it('1', 'Mléko', d1), it('2', 'Sýr', d1), it('3', 'Mléko', d2), it('4', 'Jogurt', d2)];
    expect(groupSameNames(sorted).map((i) => i.id), ['1', '3', '2', '4']);
  });

  test('repository merge: quantities add up, duplicates disappear', () async {
    final repo = DemoRepository(seed: false);
    const user = GlebaUser(uid: 'u');
    final hid = await repo.createHousehold('u', 'H');
    await repo.addItem(hid, it('', 'Jogurt', d1), user);
    await repo.addItem(hid, it('', 'Jogurt', d1, q: 2), user);
    final items = await repo.watchActiveItems(hid).first;
    final g = duplicateGroups(items).single;
    await repo.mergeItems(hid, g.first, g.sublist(1));
    final after = await repo.watchActiveItems(hid).first;
    expect(after.single.quantity, 3);
  });
}
