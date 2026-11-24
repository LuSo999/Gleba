import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/ai_retry.dart';

void main() {
  const busy = AiException('This model is currently experiencing high demand.', status: 503, transient: true);
  final attempts = <AiAttempt>[
    (provider: AiProvider.gemini, model: 'gemini-flash-latest'),
    (provider: AiProvider.gemini, model: 'gemini-flash-lite-latest'),
    (provider: AiProvider.anthropic, model: 'claude-haiku-5-5'),
  ];
  Future<void> noSleep(Duration _) async {}

  test('503 "high demand" is transient', () {
    expect(AiException.http(503, 'This model is currently experiencing high demand.').transient, isTrue);
    expect(AiException.http(429, 'quota').transient, isTrue);
    expect(AiException.http(400, 'API key not valid').transient, isFalse);
  });

  test('retries an overloaded model, then falls back to the next one', () async {
    final calls = <String?>[];
    final notes = <AiRetryNote>[];
    final r = await runWithFallback(attempts, (a) async {
      calls.add(a.model);
      if (a.model == 'gemini-flash-latest') throw busy;
      return 'ok ${a.model}';
    }, onRetry: notes.add, sleep: noSleep);
    expect(r, 'ok gemini-flash-lite-latest');
    expect(calls, ['gemini-flash-latest', 'gemini-flash-latest', 'gemini-flash-latest', 'gemini-flash-lite-latest']);
    expect(notes.map((n) => n.retry), [1, 2, 0]);
  });

  test('a non-transient error moves on without retrying; all failing throws the first error', () async {
    final calls = <String?>[];
    await expectLater(
      runWithFallback(attempts, (a) async {
        calls.add(a.model);
        throw a.provider == AiProvider.gemini ? busy : const AiException('bad key');
      }, sleep: noSleep),
      throwsA(same(busy)),
    );
    expect(calls.where((m) => m == 'claude-haiku-5-5'), hasLength(1));
  });

  test('fallback models', () {
    expect(fallbackModels(AiProvider.gemini, AiTier.fast, 'gemini-flash-latest', const []),
        ['gemini-flash-lite-latest', 'gemini-pro-latest']);
    const claude = [AiModelInfo('claude-opus-5-5'), AiModelInfo('claude-sonnet-5-5'), AiModelInfo('claude-haiku-5-5')];
    expect(fallbackModels(AiProvider.anthropic, AiTier.fast, 'claude-haiku-5-5', claude), ['claude-opus-5-5']);
  });

  test('Gemini: alias if listed, else the newest generation whatever its tiers are called', () {
    expect(
      recommendedModel(AiProvider.gemini, AiTier.fast,
          const [AiModelInfo('gemini-2.5-flash'), AiModelInfo('gemini-flash-latest'), AiModelInfo('gemini-4-hydrogen')]),
      'gemini-flash-latest',
    );
    const g4 = [AiModelInfo('gemini-2.5-flash'), AiModelInfo('gemini-2.5-pro'), AiModelInfo('gemini-4-hydrogen'), AiModelInfo('gemini-4-neon')];
    expect(recommendedModel(AiProvider.gemini, AiTier.fast, g4), 'gemini-4-hydrogen');
    expect(recommendedModel(AiProvider.gemini, AiTier.smart, g4), 'gemini-4-neon');
  });
}
