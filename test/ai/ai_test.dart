import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/ai/ai_client.dart';
import 'package:gleba/ai/ai_models.dart';
import 'package:gleba/ai/ai_tasks.dart';
import 'package:gleba/domain/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('receipt parsing tolerates code fences and fixes bad values', () {
    const reply = '''```json
{"store":"Albert","items":[
 {"name":"Bílý jogurt Olma 150 g","quantity":2,"unit":"ks","price":39.8,"isFood":true,"category":"yogurt"},
 {"name":"Igelitová taška","quantity":1,"unit":"ks","price":3,"isFood":false,"category":"other"},
 {"name":"Cibule","quantity":0.5,"unit":"kg","price":0,"isFood":true,"category":"nonsense"},
 {"name":"  ","quantity":1,"unit":"ks","price":1,"isFood":true,"category":"other"}
]}
```''';
    final lines = parseReceipt(reply);
    expect(lines.length, 3);
    expect(lines[0].quantity, 2);
    expect(lines[1].isFood, isFalse);
    expect(lines[2].price, isNull); // 0 = unknown
    expect(lines[2].categoryId, 'rootVeg'); // unknown category → guessed from the name
  });

  test('product and date parsing', () {
    final p = parseProduct('{"name":"Polotučné mléko 1 l","brand":"","category":"milk"}');
    expect((p.name, p.brand, p.categoryId), ('Polotučné mléko 1 l', null, 'milk'));
    final d = parseDate('{"date":"2026-12-05","dateType":"bestBefore"}')!;
    expect((d.date, d.type), (DateTime(2026, 12, 5), DateType.bestBefore));
    expect(parseDate('{"date":"","dateType":"unknown"}'), isNull);
  });

  test('recipe prompt lists items with days left', () {
    final now = DateTime(2026, 11, 23);
    final prompt = recipePrompt(
      [PantryItem(id: 'a', name: 'Kuřecí prsa', categoryId: 'poultry', expiryDate: DateTime(2026, 11, 24), quantity: 500, unit: 'g')],
      'do 30 minut',
      'cs',
      now,
    );
    expect(prompt, contains('- Kuřecí prsa (500 g, expires in 1 days)'));
    expect(prompt, contains('Wishes: do 30 minut'));
    expect(prompt, contains('Answer in Czech'));
  });

  test('Claude request: headers, fallbacks, structured output, image first', () async {
    late http.Request sent;
    final client = DirectAiClient(
      client: MockClient((req) async {
        sent = req;
        return http.Response(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': '{"name":"x"}'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final text = await client.run(
      AiProvider.anthropic,
      const DeviceAiKey(key: 'sk-test', model: 'claude-opus-5-5'),
      AiRequest(prompt: 'hi', images: [AiImage(Uint8List.fromList([1, 2, 3]))], schema: const {'type': 'object'}),
    );
    expect(text, '{"name":"x"}');
    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-test');
    expect(sent.headers['anthropic-version'], '2026-10-21');
    expect(sent.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['fallbacks'], 'default');
    expect(body['output_config'], {
      'effort': 'low',
      'format': {'type': 'json_schema', 'schema': {'type': 'object'}},
    });
    final content = body['messages'][0]['content'] as List;
    expect(content.first['type'], 'image');
    expect(content.last, {'type': 'text', 'text': 'hi'});
  });

  test('Claude refusal and HTTP errors become AiException', () async {
    Future<void> call(http.Response r) => DirectAiClient(client: MockClient((_) async => r))
        .run(AiProvider.anthropic, const DeviceAiKey(key: 'k', model: 'm'), const AiRequest(prompt: 'p'));
    await expectLater(call(http.Response('{"stop_reason":"refusal","content":[]}', 200)), throwsA(isA<AiException>()));
    await expectLater(
        call(http.Response('{"error":{"message":"invalid x-api-key"}}', 401)),
        throwsA(predicate((e) => e is AiException && e.message == 'invalid x-api-key')));
  });

  test('meal plan prompt and parsing', () {
    final now = DateTime(2026, 11, 23);
    final prompt = mealPlanPrompt(
      [PantryItem(id: 'a', name: 'Kuřecí prsa', categoryId: 'poultry', expiryDate: DateTime(2026, 11, 24))],
      5, ['lunch', 'dinner'], '', 'cs', now);
    expect(prompt, contains('next 5 days'));
    expect(prompt, contains('- Kuřecí prsa (expires in 1 days)'));
    final plan = parseMealPlan(
        '{"days":[{"day":0,"meals":[{"slot":"dinner","title":"Kuře na paprice","uses":["Kuřecí prsa"],"missing":["Smetana"]}]},'
        '{"day":9,"meals":[{"slot":"snack","title":"X","uses":[],"missing":[]}]}]}',
        5);
    expect(plan.length, 2);
    expect((plan[0].title, plan[0].uses.single, plan[0].missing.single), ('Kuře na paprice', 'Kuřecí prsa', 'Smetana'));
    expect((plan[1].day, plan[1].slot), (4, 'dinner')); // clamped / fixed
  });
}
