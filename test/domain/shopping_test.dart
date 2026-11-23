import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/domain/shopping.dart';

void main() {
  PantryItem item(String id, String name, double q, {String? ean, ItemStatus status = ItemStatus.active}) =>
      PantryItem(id: id, name: name, categoryId: 'milk', expiryDate: DateTime(2026, 12, 1), quantity: q, ean: ean, status: status);

  test('product key: EAN wins, otherwise a normalised name', () {
    expect(productKeyOf(item('a', 'Mléko', 1, ean: '859')), 'ean:859');
    expect(productKeyOf(item('b', '  Mléko  polotučné!', 1)), productKeyOf(item('c', 'mléko polotučné', 1)));
  });

  test('stock counts only active items of the same product', () {
    final items = [item('a', 'Mléko', 1), item('b', 'mléko', 2), item('c', 'Mléko', 5, status: ItemStatus.consumed)];
    expect(stockOf(nameKey('Mléko'), items), 3);
  });

  test('restock: below minimum and not already on the list', () {
    final rule = StockRule(productKey: nameKey('Mléko'), name: 'Mléko', minQuantity: 2);
    expect(restockNeeded([rule], [item('a', 'Mléko', 1)], const []).length, 1);
    expect(restockNeeded([rule], [item('a', 'Mléko', 2)], const []), isEmpty);
    const onList = ShoppingEntry(id: 's', name: 'mléko');
    expect(restockNeeded([rule], const [], [onList]), isEmpty);
    const bought = ShoppingEntry(id: 's', name: 'Mléko', done: true);
    expect(restockNeeded([rule], const [], [bought]).length, 1);
  });
}
