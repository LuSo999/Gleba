/// Prompts and result parsing for Gleba's AI features.
library;

import 'dart:convert';

import '../domain/models.dart';
import '../domain/shelf_life.dart';
import 'ai_models.dart';

String _lang(String code) => code == 'cs' ? 'Czech' : 'English';

final List<String> _categoryIds = [for (final c in foodCategories) c.id];

Map<String, Object?> _obj(Map<String, Object?> props) => {
      'type': 'object',
      'properties': props,
      'required': props.keys.toList(),
      'additionalProperties': false,
    };

/// Tolerates code fences or prose around the JSON (Gemini / OpenAI).
Map<String, dynamic> decodeJsonObject(String text) {
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) throw const AiException('invalid-json');
  return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
}

// ---- Receipt ---------------------------------------------------------------

class ReceiptLine {
  ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.isFood,
    required this.categoryId,
  });

  String name;
  double quantity;
  String unit;
  double? price;
  bool isFood;
  String categoryId;
}

AiRequest receiptRequest(AiImage photo, String lang) => AiRequest(
      images: [photo],
      prompt: '''
This is a photo of a shopping receipt. List every purchased line item.
- "name": a clear, human-readable product name in ${_lang(lang)}. Receipts abbreviate heavily
  (e.g. "JOG.BIL.OLM 150G" means a white Olma yogurt 150 g) – expand the abbreviation, keep the brand.
- "quantity" and "unit": how many pieces (unit "ks") or the weight/volume for loose goods (g, kg, ml, l).
  "2 x 19,90" means quantity 2.
- "price": total price paid for the line, as a number; 0 if unreadable.
- "isFood": false for non-food (drugstore, bags, deposits, discounts).
- "category": the closest of: ${_categoryIds.join(', ')}.
Skip discount lines, totals, VAT and payment lines.''',
      schema: _obj({
        'store': {'type': 'string'},
        'items': {
          'type': 'array',
          'items': _obj({
            'name': {'type': 'string'},
            'quantity': {'type': 'number'},
            'unit': {'type': 'string', 'enum': ['ks', 'g', 'kg', 'ml', 'l']},
            'price': {'type': 'number'},
            'isFood': {'type': 'boolean'},
            'category': {'type': 'string', 'enum': _categoryIds},
          }),
        },
      }),
    );

List<ReceiptLine> parseReceipt(String text) {
  final json = decodeJsonObject(text);
  return [
    for (final raw in (json['items'] as List? ?? const []))
      if (raw is Map && (raw['name'] as String?)?.trim().isNotEmpty == true)
        ReceiptLine(
          name: (raw['name'] as String).trim(),
          quantity: ((raw['quantity'] as num?)?.toDouble() ?? 1).clamp(0.01, 100000),
          unit: const ['ks', 'g', 'kg', 'ml', 'l'].contains(raw['unit']) ? raw['unit'] as String : 'ks',
          price: ((raw['price'] as num?)?.toDouble() ?? 0) > 0 ? (raw['price'] as num).toDouble() : null,
          isFood: raw['isFood'] != false,
          categoryId: _categoryIds.contains(raw['category'])
              ? raw['category'] as String
              : guessCategory(name: raw['name'] as String).id,
        ),
  ];
}

// ---- Product from a photo of the package -------------------------------------

AiRequest productRequest(AiImage photo, String lang) => AiRequest(
      images: [photo],
      prompt: 'This is a photo of a food package. Identify the product. '
          '"name": short product name in ${_lang(lang)} including the size (e.g. "Polotučné mléko 1 l"); '
          '"brand": the brand or ""; "category": the closest of: ${_categoryIds.join(', ')}.',
      schema: _obj({
        'name': {'type': 'string'},
        'brand': {'type': 'string'},
        'category': {'type': 'string', 'enum': _categoryIds},
      }),
    );

({String name, String? brand, String categoryId}) parseProduct(String text) {
  final j = decodeJsonObject(text);
  final name = (j['name'] as String? ?? '').trim();
  if (name.isEmpty) throw const AiException('empty');
  final brand = (j['brand'] as String? ?? '').trim();
  return (
    name: name,
    brand: brand.isEmpty ? null : brand,
    categoryId: _categoryIds.contains(j['category']) ? j['category'] as String : guessCategory(name: name).id,
  );
}

// ---- Expiry date from a photo --------------------------------------------------

AiRequest dateRequest(AiImage photo, DateTime today) => AiRequest(
      images: [photo],
      prompt: 'Find the expiry date printed on this food package (today is '
          '${today.toIso8601String().substring(0, 10)}). Ignore production / packing dates. '
          '"date": ISO YYYY-MM-DD, or "" if none is readable (month/year only = last day of that month). '
          '"dateType": "useBy" for "use by / spotřebujte do", "bestBefore" for '
          '"best before / minimální trvanlivost", "unknown" otherwise.',
      schema: _obj({
        'date': {'type': 'string'},
        'dateType': {'type': 'string', 'enum': ['useBy', 'bestBefore', 'unknown']},
      }),
    );

({DateTime date, DateType? type})? parseDate(String text) {
  final j = decodeJsonObject(text);
  final d = DateTime.tryParse(j['date'] as String? ?? '');
  if (d == null) return null;
  final type = switch (j['dateType']) {
    'useBy' => DateType.useBy,
    'bestBefore' => DateType.bestBefore,
    _ => null,
  };
  return (date: d, type: type);
}

// ---- Recipes -----------------------------------------------------------------

/// The same text is used for "Copy prompt" (paste into any AI chat).
String recipePrompt(List<PantryItem> items, String wishes, String lang, DateTime today) {
  final list = items.map((i) {
    final left = dateOnly(i.expiryDate).difference(dateOnly(today)).inDays;
    final q = i.quantity == i.quantity.roundToDouble() ? i.quantity.toInt() : i.quantity;
    return '- ${i.name} ($q ${i.unit}, ${left < 0 ? 'expired ${-left} days ago' : 'expires in $left days'})';
  }).join('\n');
  return '''
Suggest 3 recipes that use up these ingredients from my fridge, prioritising the ones that expire soonest.
I also have basic pantry staples (salt, pepper, oil, flour, sugar, spices).
${wishes.trim().isEmpty ? '' : 'Wishes: ${wishes.trim()}\n'}
Ingredients:
$list

For each recipe give: name, time, which listed ingredients it uses, a short ingredient list with amounts, and numbered steps.
Keep it concise. Answer in ${_lang(lang)}.''';
}
