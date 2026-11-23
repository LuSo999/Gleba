/// Core domain models for Gleba. Pure Dart – no Flutter or Firebase imports,
/// so everything here is unit-testable and shared by all data sources.
library;

enum DateType { useBy, bestBefore }

enum LocationType { fridge, freezer, pantry, other }

enum ItemStatus { active, consumed, discarded }

enum ItemSource { scan, gs1, receipt, manual, leftover }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  // Firestore Timestamp – duck typed to keep this file free of Firebase.
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

/// Strips the time component (expiry dates are whole days).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class PantryItem {
  const PantryItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.expiryDate,
    this.ean,
    this.brand,
    this.imageUrl,
    this.locationId,
    this.locationType,
    this.quantity = 1,
    this.unit = 'ks',
    this.dateType = DateType.useBy,
    this.originalExpiryDate,
    this.openedAt,
    this.frozenAt,
    this.price,
    this.source = ItemSource.manual,
    this.status = ItemStatus.active,
    this.addedBy,
    this.addedAt,
    this.householdId,
  });

  final String id;

  /// Which household the item belongs to. Not stored – filled in when items
  /// from several households are combined (notifications).
  final String? householdId;
  final String name;
  final String categoryId;
  final DateTime expiryDate;
  final String? ean;
  final String? brand;
  final String? imageUrl;
  final String? locationId;

  /// Denormalised type of [locationId] so the fridge view can place the item
  /// without loading locations first.
  final LocationType? locationType;
  final double quantity;
  final String unit;
  final DateType dateType;
  final DateTime? originalExpiryDate;
  final DateTime? openedAt;
  final DateTime? frozenAt;
  final double? price;
  final ItemSource source;
  final ItemStatus status;
  final String? addedBy;
  final DateTime? addedAt;

  PantryItem withHousehold(String hid) => PantryItem.fromMap(id, toMap(), householdId: hid);

  bool get isOpened => openedAt != null;
  bool get isFrozen => frozenAt != null;

  PantryItem copyWith({
    String? name,
    String? categoryId,
    DateTime? expiryDate,
    String? locationId,
    LocationType? locationType,
    double? quantity,
    DateType? dateType,
    DateTime? openedAt,
    DateTime? frozenAt,
    ItemStatus? status,
  }) =>
      PantryItem(
        id: id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        expiryDate: expiryDate ?? this.expiryDate,
        ean: ean,
        brand: brand,
        imageUrl: imageUrl,
        locationId: locationId ?? this.locationId,
        locationType: locationType ?? this.locationType,
        quantity: quantity ?? this.quantity,
        unit: unit,
        dateType: dateType ?? this.dateType,
        originalExpiryDate: originalExpiryDate ?? this.expiryDate,
        openedAt: openedAt ?? this.openedAt,
        frozenAt: frozenAt ?? this.frozenAt,
        price: price,
        source: source,
        status: status ?? this.status,
        addedBy: addedBy,
        addedAt: addedAt,
        householdId: householdId,
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'categoryId': categoryId,
        'expiryDate': expiryDate,
        'ean': ean,
        'brand': brand,
        'imageUrl': imageUrl,
        'locationId': locationId,
        'locationType': locationType?.name,
        'quantity': quantity,
        'unit': unit,
        'dateType': dateType.name,
        'originalExpiryDate': originalExpiryDate,
        'openedAt': openedAt,
        'frozenAt': frozenAt,
        'price': price,
        'source': source.name,
        'status': status.name,
        'addedBy': addedBy,
        'addedAt': addedAt,
      };

  factory PantryItem.fromMap(String id, Map<String, Object?> m, {String? householdId}) => PantryItem(
        id: id,
        householdId: householdId,
        name: (m['name'] as String?) ?? '',
        categoryId: (m['categoryId'] as String?) ?? 'other',
        expiryDate: _date(m['expiryDate']) ?? DateTime.now(),
        ean: m['ean'] as String?,
        brand: m['brand'] as String?,
        imageUrl: m['imageUrl'] as String?,
        locationId: m['locationId'] as String?,
        locationType: m['locationType'] == null
            ? null
            : _enumByName(LocationType.values, m['locationType'], LocationType.other),
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        unit: (m['unit'] as String?) ?? 'ks',
        dateType: _enumByName(DateType.values, m['dateType'], DateType.useBy),
        originalExpiryDate: _date(m['originalExpiryDate']),
        openedAt: _date(m['openedAt']),
        frozenAt: _date(m['frozenAt']),
        price: (m['price'] as num?)?.toDouble(),
        source: _enumByName(ItemSource.values, m['source'], ItemSource.manual),
        status: _enumByName(ItemStatus.values, m['status'], ItemStatus.active),
        addedBy: m['addedBy'] as String?,
        addedAt: _date(m['addedAt']),
      );
}

class Household {
  const Household({required this.id, required this.name, required this.memberIds});

  final String id;
  final String name;
  final List<String> memberIds;

  factory Household.fromMap(String id, Map<String, Object?> m) => Household(
        id: id,
        name: (m['name'] as String?) ?? '',
        memberIds: List<String>.from((m['memberIds'] as List?) ?? const []),
      );
}

/// Product information as returned by a lookup (household memory, shared DB
/// or Open Food Facts).
class ProductInfo {
  const ProductInfo({
    required this.ean,
    required this.name,
    this.brand,
    this.imageUrl,
    this.categoryTags = const [],
    this.allergens = const [],
    this.nutriScore,
    this.quantityLabel,
    this.categoryId,
    this.locationType,
    this.shelfLifeDays,
    this.source = 'off',
  });

  final String ean;
  final String name;
  final String? brand;
  final String? imageUrl;
  final List<String> categoryTags;
  final List<String> allergens;
  final String? nutriScore;
  final String? quantityLabel;

  /// Gleba category, if already known (learned or mapped).
  final String? categoryId;
  final LocationType? locationType;
  final int? shelfLifeDays;
  final String source;
}
