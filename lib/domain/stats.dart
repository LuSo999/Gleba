/// Household statistics computed from the history (pure, testable).
library;

import 'history.dart';
import 'models.dart';

class StatsBucket {
  StatsBucket(this.start);

  final DateTime start;
  int eaten = 0;
  int discarded = 0;
}

class CategoryWaste {
  CategoryWaste(this.categoryId);

  final String categoryId;
  int count = 0;
  double value = 0;
}

class MemberStats {
  MemberStats(this.name);

  final String name;
  int added = 0;
  int eaten = 0;
  int discarded = 0;
}

class Stats {
  Stats({
    required this.eaten,
    required this.discarded,
    required this.discardedValue,
    required this.previousDiscarded,
    required this.previousShare,
    required this.buckets,
    required this.monthly,
    required this.categories,
    required this.products,
    required this.members,
    required this.lateDiscards,
  });

  final int eaten;
  final int discarded;

  /// Kč – only items with a known price (from receipts).
  final double discardedValue;

  /// Same-length period right before this one (null for "all time").
  final int? previousDiscarded;
  final double? previousShare;

  /// Eaten vs thrown away per week (or per month for long periods).
  final List<StatsBucket> buckets;
  final bool monthly;
  final List<CategoryWaste> categories;

  /// Most often thrown away products: name → count.
  final List<MapEntry<String, int>> products;
  final List<MemberStats> members;

  /// Thrown away more than 3 days after the date – forgotten food.
  final int lateDiscards;

  int get removals => eaten + discarded;

  /// Share of eaten among everything that left the fridge (0–1).
  double get eatenShare => removals == 0 ? 0 : eaten / removals;
  double get discardedShare => removals == 0 ? 0 : discarded / removals;
}

DateTime _weekStart(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1)); // Monday
}

/// [days] = null means all time.
Stats computeStats(List<HistoryEvent> events, DateTime now, {int? days}) {
  final from = days == null ? null : dateOnly(now).subtract(Duration(days: days - 1));
  final inPeriod = events.where((e) => from == null || !e.at.isBefore(from)).toList();
  final first = inPeriod.isEmpty ? now : inPeriod.map((e) => e.at).reduce((a, b) => a.isBefore(b) ? a : b);
  final monthly = (days ?? dateOnly(now).difference(dateOnly(first)).inDays + 1) > 120;

  // Buckets cover the whole period, empty ones included (gaps are information).
  final buckets = <StatsBucket>[];
  DateTime keyOf(DateTime d) => monthly ? DateTime(d.year, d.month) : _weekStart(d);
  var cursor = keyOf(from ?? first);
  final last = keyOf(now);
  while (!cursor.isAfter(last)) {
    buckets.add(StatsBucket(cursor));
    cursor = monthly ? DateTime(cursor.year, cursor.month + 1) : cursor.add(const Duration(days: 7));
  }
  final byStart = {for (final b in buckets) b.start: b};

  var eaten = 0, discarded = 0, late = 0;
  var value = 0.0;
  final cats = <String, CategoryWaste>{};
  final products = <String, int>{};
  final members = <String, MemberStats>{};
  for (final e in inPeriod) {
    final m = members.putIfAbsent(e.byName?.isNotEmpty == true ? e.byName! : '?', () => MemberStats(e.byName ?? '?'));
    switch (e.type) {
      case HistoryType.added:
        m.added++;
      case HistoryType.consumed:
        eaten++;
        m.eaten++;
        byStart[keyOf(e.at)]?.eaten++;
      case HistoryType.discarded:
        discarded++;
        m.discarded++;
        byStart[keyOf(e.at)]?.discarded++;
        value += e.price ?? 0;
        final c = cats.putIfAbsent(e.categoryId, () => CategoryWaste(e.categoryId));
        c.count++;
        c.value += e.price ?? 0;
        products[e.name] = (products[e.name] ?? 0) + 1;
        if ((e.daysLeft ?? 0) < -3) late++;
      default:
        break;
    }
  }

  int? prevDiscarded;
  double? prevShare;
  if (from != null) {
    final prevFrom = from.subtract(Duration(days: days!));
    final prev = events.where((e) => !e.at.isBefore(prevFrom) && e.at.isBefore(from));
    final pe = prev.where((e) => e.type == HistoryType.consumed).length;
    final pd = prev.where((e) => e.type == HistoryType.discarded).length;
    if (pe + pd > 0) {
      prevDiscarded = pd;
      prevShare = pd / (pe + pd);
    }
  }

  return Stats(
    eaten: eaten,
    discarded: discarded,
    discardedValue: value,
    previousDiscarded: prevDiscarded,
    previousShare: prevShare,
    buckets: buckets,
    monthly: monthly,
    categories: cats.values.toList()..sort((a, b) => b.count.compareTo(a.count)),
    products: (products.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList(),
    members: members.values.where((m) => m.name != '?' || m.added + m.eaten + m.discarded > 0).toList()
      ..sort((a, b) => (b.added + b.eaten + b.discarded).compareTo(a.added + a.eaten + a.discarded)),
    lateDiscards: late,
  );
}

enum TipKind { topCategory, forgotten, improving, great }

class StatsTip {
  const StatsTip(this.kind, {this.categoryId});

  final TipKind kind;
  final String? categoryId;
}

/// A few rule-based, actionable observations.
List<StatsTip> statsTips(Stats s) {
  final tips = <StatsTip>[];
  if (s.removals >= 5 && s.discardedShare <= 0.1) tips.add(const StatsTip(TipKind.great));
  if (s.previousShare != null && s.discardedShare < s.previousShare! - 0.05) tips.add(const StatsTip(TipKind.improving));
  final top = s.categories.firstOrNull;
  if (top != null && top.count >= 3 && top.count / s.discarded >= 0.3) {
    tips.add(StatsTip(TipKind.topCategory, categoryId: top.categoryId));
  }
  if (s.discarded >= 3 && s.lateDiscards / s.discarded >= 0.5) tips.add(const StatsTip(TipKind.forgotten));
  return tips;
}
