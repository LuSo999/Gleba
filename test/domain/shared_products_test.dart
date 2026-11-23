import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/data/demo_repository.dart';
import 'package:gleba/data/open_food_facts.dart';
import 'package:gleba/data/product_lookup.dart';
import 'package:gleba/data/repository.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/domain/shared_products.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('only real, global barcodes are shared', () {
    expect(isShareableEan('8594001021499'), isTrue);
    expect(isShareableEan('96385074'), isTrue);
    expect(isShareableEan('2912345000004'), isFalse); // in-store code
    expect(isShareableEan('8594001021490'), isFalse); // bad check digit
    expect(isShareableEan(null), isFalse);
  });

  test('shelf life is a running average that resists typos', () {
    var s = const ShelfLifeStats();
    for (final d in [10, 12, 14]) {
      s = s.add(d);
    }
    expect(s.suggestedDays, 12);
    s = s.add(3000); // a 2027 → 2035 slip
    expect(s.count, 4);
    expect(s.suggestedDays, 18); // clamped to 3× the average (36) before averaging
  });

  test('lookup order: household → Gleba → Open Food Facts', () async {
    var offCalls = 0;
    final off = OpenFoodFactsClient(
      client: MockClient((_) async {
        offCalls++;
        return http.Response('{"status":0}', 404);
      }),
    );
    final repo = DemoRepository(seed: false);
    final lookup = ProductLookup(repo, off);
    const ean = '8594001021499';
    const user = GlebaUser(uid: 'u', displayName: 'U');

    expect(await lookup.lookup('h', ean), isNull);
    expect(offCalls, 1);

    // Someone in another household adds it with a package date 20 days ahead.
    final item = PantryItem(id: '', name: 'Jogurt Clever', categoryId: 'yogurt', ean: ean, expiryDate: DateTime.now());
    await repo.contributeProduct(item, shelfLifeDays: 20);
    final shared = await ProductLookup(repo, off).lookup('h', ean);
    expect((shared!.name, shared.source, shared.shelfLifeDays), ('Jogurt Clever', 'gleba', 20));
    expect(offCalls, 1); // not asked again

    // Our household's own name wins, the community shelf life is kept.
    await repo.addItem('h', PantryItem(id: '', name: 'Náš jogurt', categoryId: 'yogurt', ean: ean, expiryDate: DateTime.now()), user);
    final own = await ProductLookup(repo, off).lookup('h', ean);
    expect(own!.name, 'Náš jogurt');
    expect(own.shelfLifeDays, isNotNull);
  });
}
