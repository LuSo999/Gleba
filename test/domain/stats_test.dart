import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/history.dart';
import 'package:gleba/domain/stats.dart';

void main() {
  final now = DateTime(2026, 11, 23, 12); // Monday
  HistoryEvent ev(HistoryType t, int daysAgo,
          {String cat = 'yogurt', String name = 'Jogurt', double? price, String by = 'Jana', int? daysLeft}) =>
      HistoryEvent(
          id: '$t$daysAgo$name', itemId: 'i', type: t, at: now.subtract(Duration(days: daysAgo)),
          name: name, categoryId: cat, price: price, byName: by, daysLeft: daysLeft);

  test('totals, shares, money and weekly buckets', () {
    final events = [
      ev(HistoryType.consumed, 0),
      ev(HistoryType.consumed, 1),
      ev(HistoryType.consumed, 8),
      ev(HistoryType.discarded, 2, price: 19.9, daysLeft: -5),
      ev(HistoryType.added, 3, by: 'Luboš'),
      ev(HistoryType.discarded, 40), // outside a 30-day window
    ];
    final s = computeStats(events, now, days: 30);
    expect((s.eaten, s.discarded), (3, 1));
    expect(s.eatenShare, 0.75);
    expect(s.discardedValue, 19.9);
    expect(s.lateDiscards, 1);
    expect(s.monthly, isFalse);
    expect(s.buckets.last.start, DateTime(2026, 11, 23));
    expect((s.buckets.last.eaten, s.buckets.last.discarded), (1, 0));
    final prevWeek = s.buckets[s.buckets.length - 2];
    expect((prevWeek.eaten, prevWeek.discarded), (1, 1));
    expect(s.buckets.length, 6); // 25 Oct (a Sunday) … 23 Nov spans 6 calendar weeks
    expect(s.previousDiscarded, 1); // the discard 40 days ago falls into the previous 30 days
    expect(s.members.map((m) => m.name), ['Jana', 'Luboš']);
  });

  test('a year is shown by month', () {
    final s = computeStats([ev(HistoryType.consumed, 200)], now, days: 365);
    expect(s.monthly, isTrue);
    expect(s.buckets.first.start, DateTime(2025, 11));
    expect(s.buckets.length, 13);
  });

  test('tips', () {
    final events = [
      for (var i = 0; i < 4; i++) ev(HistoryType.discarded, i, daysLeft: -6),
      ev(HistoryType.discarded, 1, cat: 'bread', name: 'Chléb'),
      for (var i = 0; i < 5; i++) ev(HistoryType.consumed, i),
    ];
    final tips = statsTips(computeStats(events, now, days: 30));
    expect(tips.map((t) => t.kind), [TipKind.topCategory, TipKind.forgotten]);
    expect(tips.first.categoryId, 'yogurt');
  });
}
