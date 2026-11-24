import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/ai_service.dart';
import 'package:gleba/ui/screens/receipt_screen.dart';
import 'package:image_picker/image_picker.dart';

/// AI that answers when the test says so.
class _SlowAi extends AiService {
  _SlowAi(super.ref);

  final answer = Completer<String>();

  @override
  bool enabledFor(AiFeature f) => true;

  @override
  Future<String> run(AiFeature f, AiRequest r, {void Function(AiRetryNote note)? onRetry}) => answer.future;
}

void main() {
  test('receipt job runs outside the screen and keeps its result', () async {
    late _SlowAi ai;
    final c = ProviderContainer(overrides: [aiServiceProvider.overrideWith((ref) => ai = _SlowAi(ref))]);
    addTearDown(c.dispose);
    final sub = c.listen(receiptJobProvider, (_, _) {}); // like a screen watching it
    final job = c.read(receiptJobProvider.notifier).start(XFile.fromData(Uint8List.fromList([1, 2, 3])), 'cs');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(receiptJobProvider).stage, ReceiptStage.working);
    expect(c.read(receiptJobProvider).busy, isTrue);

    sub.close(); // the screen is gone (rotation, back button…) – the job goes on
    ai.answer.complete('{"store":"Albert","items":[{"name":"Mléko","quantity":2,"unit":"ks","price":49.8,"isFood":true,"category":"milk"}]}');
    await job;

    final s = c.read(receiptJobProvider);
    expect(s.stage, ReceiptStage.done);
    expect(s.lines!.single.line.name, 'Mléko');
    expect(s.lines!.single.selected, isTrue);
  });
}
