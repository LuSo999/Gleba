import '../domain/models.dart';
import 'open_food_facts.dart';
import 'repository.dart';

/// Looks a barcode up in order: household memory → Open Food Facts.
/// (Shared Gleba product DB is planned – see docs/zdroje-dat.md.)
class ProductLookup {
  ProductLookup(this._repo, this._off);

  final GlebaRepository _repo;
  final OpenFoodFactsClient _off;
  final _cache = <String, ProductInfo?>{};

  Future<ProductInfo?> lookup(String householdId, String ean) async {
    final own = await _repo.householdProduct(householdId, ean);
    if (own != null) return own;
    if (_cache.containsKey(ean)) return _cache[ean];
    return _cache[ean] = await _off.lookup(ean);
  }
}
