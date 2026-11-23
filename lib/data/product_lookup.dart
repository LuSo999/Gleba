import '../domain/models.dart';
import 'open_food_facts.dart';
import 'repository.dart';

/// Looks a barcode up in order: household memory → Gleba's shared product
/// database → Open Food Facts.
class ProductLookup {
  ProductLookup(this._repo, this._off);

  final GlebaRepository _repo;
  final OpenFoodFactsClient _off;
  final _cache = <String, ProductInfo?>{};

  Future<ProductInfo?> lookup(String householdId, String ean) async {
    final own = await _repo.householdProduct(householdId, ean);
    if (own != null) {
      if (own.shelfLifeDays != null) return own;
      // Our own name/category, but the community's typical shelf life.
      final shared = await _shared(ean);
      return shared?.shelfLifeDays == null
          ? own
          : ProductInfo(
              ean: ean, name: own.name, brand: own.brand, imageUrl: own.imageUrl, categoryId: own.categoryId,
              locationType: own.locationType, shelfLifeDays: shared!.shelfLifeDays, source: own.source);
    }
    final shared = await _shared(ean);
    if (shared != null) return shared;
    if (_cache.containsKey(ean)) return _cache[ean];
    return _cache[ean] = await _off.lookup(ean);
  }

  Future<ProductInfo?> _shared(String ean) async {
    try {
      return await _repo.sharedProduct(ean);
    } catch (_) {
      return null; // offline – fall through to the next source
    }
  }
}
