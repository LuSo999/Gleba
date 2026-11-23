import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/freshness.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/domain/notification_rules.dart';

void main() {
  final now = DateTime(2026, 11, 23, 12);
  PantryItem item(String id, String cat, DateTime exp, {DateType type = DateType.useBy, String? ean}) =>
      PantryItem(id: id, name: id, categoryId: cat, expiryDate: exp, dateType: type, ean: ean);

  test('product beats category beats default', () {
    final rules = [
      const NotificationRule(scope: RuleScope.defaults, daysBefore: 2),
      const NotificationRule(scope: RuleScope.category, targetId: 'milk', daysBefore: 1),
      const NotificationRule(scope: RuleScope.product, targetId: '123', enabled: false),
    ];
    expect(resolveRule(item('a', 'cheeseHard', now), rules).daysBefore, 2);
    expect(resolveRule(item('b', 'milk', now), rules).daysBefore, 1);
    expect(resolveRule(item('c', 'milk', now, ean: '123'), rules).enabled, isFalse);
  });

  test('date-type specific rule wins within scope', () {
    final rules = [
      const NotificationRule(scope: RuleScope.defaults, daysBefore: 2),
      const NotificationRule(scope: RuleScope.defaults, dateType: DateType.bestBefore, daysBefore: 0),
    ];
    expect(resolveRule(item('a', 'x', now, type: DateType.bestBefore), rules).daysBefore, 0);
    expect(resolveRule(item('b', 'x', now), rules).daysBefore, 2);
  });

  test('freshness and urgency ordering', () {
    final a = item('expired', 'milk', DateTime(2026, 11, 22));
    final b = item('bb', 'milk', DateTime(2026, 11, 20), type: DateType.bestBefore);
    final c = item('today', 'milk', DateTime(2026, 11, 23));
    final d = item('fresh', 'milk', DateTime(2026, 12, 23));
    expect(freshnessOf(b, now), Freshness.pastBestBefore);
    expect(sortByUrgency([d, b, c, a], now).map((i) => i.id), ['expired', 'today', 'bb', 'fresh']);
  });

  test('rules and prefs survive a round trip', () {
    const r = NotificationRule(
        scope: RuleScope.product, targetId: '859', dateType: DateType.bestBefore, enabled: false, daysBefore: 5,
        hour: 18, minute: 15, label: 'Jogurt');
    final back = NotificationRule.fromMap(r.toMap());
    expect(back.key, r.key);
    expect((back.enabled, back.daysBefore, back.hour, back.minute, back.label), (false, 5, 18, 15, 'Jogurt'));
    const p = NotificationPrefs(
        itemNotifications: false, morningDigest: true, digestHour: 6, digestMinute: 45,
        repeatExpired: false, othersActivity: true, quietEnabled: true, quietFrom: 1380, quietTo: 360);
    final pb = NotificationPrefs.fromMap(p.toMap());
    expect((pb.itemNotifications, pb.morningDigest, pb.digestHour, pb.digestMinute), (false, true, 6, 45));
    expect((pb.repeatExpired, pb.othersActivity, pb.quietEnabled, pb.quietFrom, pb.quietTo), (false, true, true, 1380, 360));
    expect(NotificationPrefs.fromMap(null).repeatExpired, isTrue);
    expect(NotificationPrefs.fromMap(null).itemNotifications, isTrue);
  });
}
