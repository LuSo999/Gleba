import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/shelf_life.dart';

/// Client for the Open Food Facts product API (https://world.openfoodfacts.org).
/// Free, open data (ODbL). No API key needed; OFF asks clients to send a
/// descriptive User-Agent.
class OpenFoodFactsClient {
  OpenFoodFactsClient({http.Client? client, this.languageCode = 'cs'}) : _client = client ?? http.Client();

  final http.Client _client;
  final String languageCode;

  static const _fields =
      'product_name,product_name_cs,product_name_en,generic_name_cs,brands,image_front_small_url,'
      'categories_tags,allergens_tags,nutriscore_grade,quantity,nutriments,serving_quantity,product_quantity';

  Future<ProductInfo?> lookup(String ean) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$ean.json', {'fields': _fields});
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': 'Gleba/0.1 (open-source pantry app)'})
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null; // offline or slow – caller falls back to manual entry
    }
    if (res.statusCode != 200) return null;
    return parseOffResponse(ean, jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>, languageCode);
  }
}

ProductInfo? parseOffResponse(String ean, Map<String, dynamic> json, String languageCode) {
  if (json['status'] != 1 || json['product'] is! Map) return null;
  final p = json['product'] as Map<String, dynamic>;
  String? str(String k) {
    final v = p[k];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final name =
      str('product_name_$languageCode') ?? str('product_name') ?? str('product_name_en') ?? str('generic_name_cs');
  if (name == null) return null;
  final tags = List<String>.from((p['categories_tags'] as List?) ?? const []);
  final category = guessCategory(tags: tags, name: name);
  return ProductInfo(
    ean: ean,
    name: name,
    brand: str('brands')?.split(',').first.trim(),
    imageUrl: str('image_front_small_url'),
    categoryTags: tags,
    allergens: List<String>.from((p['allergens_tags'] as List?) ?? const [])
        .map((a) => a.replaceFirst(RegExp(r'^\w{2}:'), ''))
        .toList(),
    nutriScore: switch (str('nutriscore_grade')) {
      final g? when RegExp(r'^[a-e]$').hasMatch(g) => g.toUpperCase(),
      _ => null,
    },
    quantityLabel: str('quantity'),
    categoryId: category.id,
    locationType: category.defaultLocation,
    source: 'off',
    nutrition: _nutrition(p),
  );
}

Nutrition? _nutrition(Map<String, dynamic> p) {
  final n = p['nutriments'];
  if (n is! Map) return null;
  double? v(String k) {
    final x = n[k];
    return x is num ? x.toDouble() : (x is String ? double.tryParse(x) : null);
  }

  double? g(Object? x) => x is num ? x.toDouble() : (x is String ? double.tryParse(x) : null);
  final kcal = v('energy-kcal_100g') ?? (v('energy_100g') == null ? null : v('energy_100g')! / 4.184);
  if (kcal == null) return null;
  return Nutrition(
    kcal: kcal,
    protein: v('proteins_100g'),
    carbs: v('carbohydrates_100g'),
    fat: v('fat_100g'),
    sugar: v('sugars_100g'),
    fiber: v('fiber_100g'),
    salt: v('salt_100g'),
    servingGrams: g(p['serving_quantity']),
    packageGrams: g(p['product_quantity']),
  );
}
