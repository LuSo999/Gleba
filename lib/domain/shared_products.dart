/// Gleba's shared product database: what users entered for a barcode, plus
/// how long the product usually lasts. No personal data is stored.
library;

import 'gs1_parser.dart';

/// Only real, globally unique barcodes are shared. In-store codes (20–29,
/// weighed goods, bakery) mean different things in every shop.
bool isShareableEan(String? ean) {
  if (ean == null || !(ean.length == 8 || ean.length == 13) || !isValidGtin(ean)) return false;
  if (ean.length == 13) {
    final prefix = int.parse(ean.substring(0, 2));
    if (prefix >= 20 && prefix <= 29) return false;
  }
  return true;
}

class ShelfLifeStats {
  const ShelfLifeStats({this.count = 0, this.avgDays = 0});

  /// How many purchases with a package date were averaged.
  final int count;
  final double avgDays;

  /// Running average. Dates far off the average (typos, a 2027 → 2072 slip)
  /// are clamped so one mistake can't ruin it.
  ShelfLifeStats add(int days) {
    var d = days.clamp(0, 3650).toDouble();
    if (count >= 3) d = d.clamp(avgDays / 3, avgDays * 3);
    return ShelfLifeStats(count: count + 1, avgDays: (avgDays * count + d) / (count + 1));
  }

  int? get suggestedDays => count == 0 ? null : avgDays.round();

  Map<String, Object?> toMap() => {'count': count, 'avgDays': avgDays};

  factory ShelfLifeStats.fromMap(Object? m) => m is Map
      ? ShelfLifeStats(count: (m['count'] as num?)?.toInt() ?? 0, avgDays: (m['avgDays'] as num?)?.toDouble() ?? 0)
      : const ShelfLifeStats();
}
