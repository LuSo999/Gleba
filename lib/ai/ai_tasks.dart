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
This is a photo or screenshot of a shopping receipt (often Czech: Lidl, Albert, Billa, Kaufland,
Penny, Tesco, Globus, Rohlik…). It may be long – read it top to bottom and list EVERY purchased line item.
- "name": a clear, human-readable product name in ${_lang(lang)}. Receipts abbreviate heavily
  (e.g. "JOG.BIL.OLM 150G" means a white Olma yogurt 150 g, "Čist.vlhč.ubr." means wet wipes)
  – expand the abbreviation, keep the brand. Drop leading article numbers (e.g. "514215 Aut.deštník" → "Automatický deštník").
- "quantity" and "unit": how many pieces (unit "ks") or the weight/volume for loose goods (g, kg, ml, l).
  The multiplier is often on the next line: "6 ks x 3,90 Kč/ks" means quantity 6 of the item above;
  "2 x 19,90" means quantity 2; "M 0,140 kg x 259,00 Kč/kg" means 0.14 kg.
  If the name contains a pack size (e.g. "Šlehačka 250 ml"), keep it in the name and count pieces.
- "price": total price paid for the line after its discounts, as a number (use "Cena po slevě" /
  "price after discount" when present); 0 if unreadable.
- "isFood": false for non-food (drugstore, cosmetics, household goods, bags, deposits).
- "category": the closest of: ${_categoryIds.join(', ')}.
Discount lines ("Lidl Plus sleva", "4+2 zdarma", "Sleva", negative amounts), "Cena po slevě", warranty notes
("Záruka: 3 roky"), totals ("K PLATBĚ", "Celkem"), VAT, payment, loyalty points and store info are NOT items.''',
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

// ---- Meal plan -------------------------------------------------------------------

/// The same text is used for "Copy prompt" and (with a schema) for the AI call.
String mealPlanPrompt(List<PantryItem> items, int days, List<String> slots, String wishes, String lang, DateTime today) {
  final list = items.map((i) {
    final left = dateOnly(i.expiryDate).difference(dateOnly(today)).inDays;
    return '- ${i.name} (${left < 0 ? 'expired ${-left} days ago' : 'expires in $left days'})';
  }).join('\n');
  return '''
Plan home meals for the next $days days (day 0 = today) – meals: ${slots.join(', ')}.
Use up the ingredients I have, the ones expiring soonest first; avoid waste. Keep it realistic for a household:
reuse leftovers, simple everyday dishes. Basic pantry staples (salt, oil, flour, spices) are available.
${wishes.trim().isEmpty ? '' : 'Wishes: ${wishes.trim()}\n'}
In my fridge:
$list

For each meal: a short dish title, which of MY ingredients it uses (exact names from the list), and what I'd need to buy.
Answer in ${_lang(lang)}.''';
}

AiRequest mealPlanRequest(String prompt) => AiRequest(
      prompt: prompt,
      schema: _obj({
        'days': {
          'type': 'array',
          'items': _obj({
            'day': {'type': 'integer'},
            'meals': {
              'type': 'array',
              'items': _obj({
                'slot': {'type': 'string', 'enum': ['breakfast', 'lunch', 'dinner']},
                'title': {'type': 'string'},
                'uses': {'type': 'array', 'items': {'type': 'string'}},
                'missing': {'type': 'array', 'items': {'type': 'string'}},
              }),
            },
          }),
        },
      }),
    );

class PlannedMeal {
  const PlannedMeal({required this.day, required this.slot, required this.title, required this.uses, required this.missing});

  final int day;
  final String slot;
  final String title;
  final List<String> uses;
  final List<String> missing;
}

List<PlannedMeal> parseMealPlan(String text, int days) {
  final json = decodeJsonObject(text);
  return [
    for (final d in (json['days'] as List? ?? const []))
      if (d is Map)
        for (final m in (d['meals'] as List? ?? const []))
          if (m is Map && (m['title'] as String?)?.trim().isNotEmpty == true)
            PlannedMeal(
              day: ((d['day'] as num?)?.toInt() ?? 0).clamp(0, days - 1),
              slot: const ['breakfast', 'lunch', 'dinner'].contains(m['slot']) ? m['slot'] as String : 'dinner',
              title: (m['title'] as String).trim(),
              uses: [for (final u in (m['uses'] as List? ?? const [])) '$u'],
              missing: [for (final u in (m['missing'] as List? ?? const [])) '$u'],
            ),
  ];
}
