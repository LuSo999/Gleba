// ignore_for_file: avoid_print
// Live check against the real providers – NOT part of the normal test run.
// Runs only with a key in the environment (GitHub workflow "AI live test"):
//   GEMINI_API_KEY=… flutter test test_ai
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_client.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/ai_retry.dart';
import 'package:gleba/ai/ai_tasks.dart';
import 'package:gleba/ai/image_split.dart';

const _envKeys = {
  AiProvider.gemini: 'GEMINI_API_KEY',
  AiProvider.openai: 'OPENAI_API_KEY',
  AiProvider.anthropic: 'ANTHROPIC_API_KEY',
};

void main() {
  final client = DirectAiClient();
  final keys = {
    for (final e in _envKeys.entries)
      if ((Platform.environment[e.value] ?? '').isNotEmpty) e.key: Platform.environment[e.value]!,
  };
  final models = <AiProvider, List<AiModelInfo>>{};

  setUpAll(() async {
    for (final p in keys.keys) {
      models[p] = await client.listModels(p, keys[p]!);
      print('== ${aiProviderNames[p]}: ${models[p]!.length} models');
      for (final m in models[p]!) {
        print('   ${m.id}${m.name == null ? '' : '  (${m.name})'}');
      }
      print('   recommended fast: ${recommendedModel(p, AiTier.fast, models[p]!)}'
          ', smart: ${recommendedModel(p, AiTier.smart, models[p]!)}');
    }
  });

  Future<T> run<T>(AiProvider p, AiFeature f, AiRequest r, T Function(String) parse) async {
    final primary = recommendedModel(p, tierOf(f), models[p]!) ?? defaultAiModels[p]!;
    final attempts = <AiAttempt>[
      (provider: p, model: primary),
      for (final m in fallbackModels(p, tierOf(f), primary, models[p]!)) (provider: p, model: m),
    ];
    final sw = Stopwatch()..start();
    var used = primary;
    final res = await runWithFallback(attempts, (a) async {
      used = a.model!;
      final text = await client.run(p, DeviceAiKey(key: keys[p]!, model: a.model!), r);
      print('   raw reply from ${a.model} (${text.length} chars): '
          '${text.length > 300 ? '${text.substring(0, 300)}…' : text}');
      return parse(text);
    }, onRetry: (n) => print('   ↻ retry ${n.retry} → ${n.attempt.model}'));
    print('   ✓ ${f.name} with $used in ${sw.elapsed.inSeconds} s');
    return res;
  }

  AiImage img(String name) => AiImage(File('test_ai/fixtures/$name').readAsBytesSync(),
      mime: name.endsWith('.png') ? 'image/png' : 'image/jpeg');

  void printLines(List<ReceiptLine> lines) {
    for (final l in lines) {
      print('   ${l.isFood ? '🍞' : '🧴'} ${l.name.padRight(38)} ${'${l.quantity} ${l.unit}'.padRight(9)}'
          ' ${l.price?.toStringAsFixed(2) ?? '-'} Kč  [${l.categoryId}]');
    }
    final sum = lines.fold<double>(0, (s, l) => s + (l.price ?? 0));
    print('   ${lines.length} items, sum ${sum.toStringAsFixed(2)} Kč');
  }

  for (final p in AiProvider.values) {
    final skip = keys.containsKey(p) ? false : 'no ${_envKeys[p]}';
    group(aiProviderNames[p]!, () {
      test('short Lidl receipt (discounts, "6 ks x" on the next line)', () async {
        final lines = await run(p, AiFeature.receipt, receiptRequest(splitTallImage(img('receipt_short.png')), 'cs'), parseReceipt);
        printLines(lines);
        expect(lines.length, inInclusiveRange(6, 8));
        final bageta = lines.firstWhere((l) => l.name.toLowerCase().contains('bage'));
        expect(bageta.quantity, 6);
        expect(bageta.price, closeTo(15.6, 0.01));
        final umbrella = lines.firstWhere((l) => l.name.toLowerCase().contains('deštník'));
        expect(umbrella.isFood, isFalse);
        expect(lines.fold<double>(0, (s, l) => s + (l.price ?? 0)), closeTo(364.70, 5));
      }, skip: skip, timeout: const Timeout(Duration(minutes: 6)));

      test('long Lidl receipt (~95 lines, low resolution)', () async {
        final lines = await run(p, AiFeature.receipt, receiptRequest(splitTallImage(img('receipt_long.jpg')), 'cs'), parseReceipt);
        printLines(lines);
        expect(lines.length, greaterThan(70));
      }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));

      test('expiry date from a label photo', () async {
        final res = await run(p, AiFeature.date, dateRequest(img('date_label.jpg'), DateTime(2026, 11, 24)), parseDate);
        print('   date: ${res?.date} ${res?.type}');
        expect(res?.date, DateTime(2026, 11, 28));
      }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));
    });
  }
}
