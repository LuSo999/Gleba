import 'models.dart';

/// How urgent an item is. Drives colours in the fridge and list ordering.
enum Freshness {
  /// Plenty of time left.
  fresh,

  /// Within the "soon" window (default 2 days).
  soon,

  /// Expires today.
  today,

  /// Past a "use by" date – should not be eaten.
  expired,

  /// Past a "best before" date – usually still fine, check it.
  pastBestBefore,
}

int daysLeft(DateTime expiry, DateTime now) =>
    dateOnly(expiry).difference(dateOnly(now)).inDays;

Freshness freshnessOf(PantryItem item, DateTime now, {int soonDays = 2}) {
  final left = daysLeft(item.expiryDate, now);
  if (left < 0) {
    return item.dateType == DateType.useBy ? Freshness.expired : Freshness.pastBestBefore;
  }
  if (left == 0) return Freshness.today;
  if (left <= soonDays) return Freshness.soon;
  return Freshness.fresh;
}

/// Sorts by urgency: expired use-by first, then by date. Past best-before items
/// go after today's items (they are less dangerous than an expiring use-by).
List<PantryItem> sortByUrgency(Iterable<PantryItem> items, DateTime now) {
  int rank(PantryItem i) => switch (freshnessOf(i, now)) {
        Freshness.expired => 0,
        Freshness.today => 1,
        Freshness.pastBestBefore => 2,
        Freshness.soon => 3,
        Freshness.fresh => 4,
      };
  final list = items.toList();
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.expiryDate.compareTo(b.expiryDate);
  });
  return list;
}
