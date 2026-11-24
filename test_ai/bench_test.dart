// ignore_for_file: avoid_print
// Compares models on the sample receipts: one try each, no fallback.
//   GEMINI_API_KEY=… BENCH_MODELS="gemini-4-hydrogen,gemini-3.8-flash" flutter test test_ai/bench_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_client.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/ai_tasks.dart';

void main() {
  final key = Platform.environment['GEMINI_API_KEY'] ?? '';
  final models = (Platform.environment['BENCH_MODELS'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
  final client = DirectAiClient();
  AiImage img(String name) => AiImage(File('test_ai/fixtures/$name').readAsBytesSync(),
      mime: name.endsWith('.png') ? 'image/png' : 'image/jpeg');

  test('benchmark', () async {
    final rows = <String>[];
    for (final m in models) {
      for (final (fixture, expectSum) in [('receipt_short.png', 364.70), ('receipt_long.jpg', 5932.32)]) {
        final sw = Stopwatch()..start();
        String row;
        try {
          final text = await client.run(AiProvider.gemini, DeviceAiKey(key: key, model: m), receiptRequest(img(fixture), 'cs'));
          final lines = parseReceipt(text);
          final sum = lines.fold<double>(0, (s, l) => s + (l.price ?? 0));
          final bageta = lines.where((l) => l.name.toLowerCase().contains('bage')).firstOrNull;
          row = 'OK   ${lines.length} items, sum ${sum.toStringAsFixed(2)} (want $expectSum, '
              '${(100 * (sum - expectSum) / expectSum).toStringAsFixed(1)} %)'
              '${bageta == null ? '' : ', bageta ${bageta.quantity} ${bageta.unit} ${bageta.price}'}';
          if (fixture.contains('long')) {
            for (final l in lines) {
              print('     $m | ${l.isFood ? 'F' : '-'} ${l.name} | ${l.quantity} ${l.unit} | ${l.price} | ${l.categoryId}');
            }
          }
        } catch (e) {
          row = 'FAIL ${'$e'.split('\n').first}';
        }
        rows.add('${m.padRight(28)} ${fixture.padRight(18)} ${'${sw.elapsed.inMilliseconds / 1000}'.padLeft(6)} s  $row');
        print(rows.last);
      }
    }
    print('\n===== SUMMARY =====\n${rows.join('\n')}');
  }, skip: key.isEmpty || models.isEmpty ? 'no key / BENCH_MODELS' : false, timeout: const Timeout(Duration(minutes: 30)));
}
