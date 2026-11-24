import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_tasks.dart';
import 'package:gleba/app_state.dart';
import 'package:gleba/data/demo_repository.dart';
import 'package:gleba/domain/batch.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/ui/batch/batch_job.dart';

BatchReceiptLine line(String name, {double q = 1, double? price, bool food = true, String cat = 'other'}) =>
    BatchReceiptLine(name: name, quantity: q, unit: 'ks', price: price, isFood: food, categoryId: cat);

void main() {
  test('abbreviated receipt lines match product names', () {
    expect(nameSimilarity('Selské máslo 84 %', 'Selské máslo 84%'), greaterThan(0.8));
    expect(nameSimilarity('Čisticí vlhčené ubrousky', 'Čist.vlhč.ubr.koup'), greaterThan(0.6));
    expect(nameSimilarity('Lipánek mléko čoko', 'Kinder Paradiso'), lessThan(0.2));
  });

  test('pairing is one-to-one, best first, and skips weak matches', () {
    final a = BatchProduct(id: 'a')..name = 'Selské máslo 84 %';
    final b = BatchProduct(id: 'b')..name = 'Lipánek čoko';
    final c = BatchProduct(id: 'c')..name = 'Jihočeská Niva';
    final lines = [line('Lipánek mléko čoko'), line('Selské máslo 84%'), line('Bagetka')];
    expect(pairWithReceipt([a, b, c], lines), {'a': 1, 'b': 0});
  });

  test('a series: barcode → database, date from the photo, skipped date, receipt pairing, save', () async {
    final tmp = Directory.systemTemp.createTempSync('gleba-batch');
    String photo(String n) => (File('${tmp.path}/$n.jpg')..writeAsBytesSync([1, 2, 3])).path;
    final repo = DemoRepository();
    final auth = DemoAuthService();
    await auth.signInWithGoogle();
    final c = ProviderContainer(overrides: [
      isDemoProvider.overrideWithValue(true),
      authServiceProvider.overrideWithValue(auth),
      repositoryProvider.overrideWithValue(repo),
      batchProcessorsProvider.overrideWithValue(BatchProcessors(
        scanBarcode: (p) async => p.contains('butter') ? '8594003170010' : null,
        lookup: (ean) async => const ProductInfo(ean: '8594003170010', name: 'Selské máslo 84 %', categoryId: 'butter'),
        ocr: (p) async => 'MINIMÁLNÍ TRVANLIVOST DO: 12.12.2030',
        aiProduct: (_) async => (name: 'Lipánek čoko', brand: null, categoryId: 'yogurt'),
        aiDate: (_) async => null,
        aiReceipt: (_) async => [
          ReceiptLine(name: 'Selské máslo 84%', quantity: 1, unit: 'ks', price: 49.9, isFood: true, categoryId: 'butter'),
          ReceiptLine(name: 'Lipánek mléko čoko', quantity: 2, unit: 'ks', price: 39.8, isFood: true, categoryId: 'yogurt'),
          ReceiptLine(name: 'Rajčata cherry', quantity: 1, unit: 'ks', price: 34.9, isFood: true, categoryId: 'vegetables'),
          ReceiptLine(name: 'Pap. taška', quantity: 1, unit: 'ks', price: 4.9, isFood: false, categoryId: 'other'),
        ],
      )),
    ]);
    addTearDown(c.dispose);
    // Wait for the signed-in user and the household.
    c.listen(activeHouseholdProvider, (_, _) {});
    c.listen(userProvider, (_, _) {});
    await c.read(householdsProvider.future);
    await c.read(userProvider.future);

    final job = c.read(batchJobProvider.notifier);
    job.addBarcodePhoto(photo('butter'));
    expect(job.awaitingDateFor, isNotNull);
    job.addDatePhoto(photo('butter-date'));
    job.addBarcodePhoto(photo('yogurt')); // no barcode found → AI recognises it
    job.skipDate();
    await job.addReceipt(File(photo('receipt')).readAsBytesSync());
    while (job.processing > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final rows = job.rows(now: DateTime(2026, 11, 24));
    expect(rows.map((r) => r.item.name), ['Selské máslo 84 %', 'Lipánek čoko', 'Rajčata cherry', 'Pap. taška']);
    final butter = rows[0];
    expect(butter.item.expiryDate, DateTime(2030, 12, 12));
    expect(butter.item.price, 49.9);
    expect(butter.item.ean, '8594003170010');
    final yogurt = rows[1];
    expect(yogurt.dateSource, DateSource.estimate);
    expect(yogurt.item.quantity, 2); // from the receipt
    expect(rows[2].fromReceiptOnly, isTrue);
    expect(job.isSelected(rows[3]), isFalse); // the bag isn't food

    final before = (await repo.watchActiveItems('home').first).length;
    expect(await job.save(), 3);
    expect((await repo.watchActiveItems('home').first).length, before + 3);
    expect(job.isEmpty, isTrue);
  });
}
