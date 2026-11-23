/// Layered notification rules: default → category → product.
/// The most specific enabled-or-disabled rule wins, so a user can e.g. turn
/// notifications off for "drinks" but keep them on for one particular juice.
library;

import 'freshness.dart';
import 'models.dart';

enum RuleScope { defaults, category, product }

class NotificationRule {
  const NotificationRule({
    required this.scope,
    this.targetId,
    this.dateType,
    this.enabled = true,
    this.daysBefore = 2,
    this.hour = 9,
    this.minute = 0,
  });

  final RuleScope scope;

  /// Category id for [RuleScope.category], item id or EAN for [RuleScope.product].
  final String? targetId;

  /// When set, applies only to items with this date type.
  final DateType? dateType;
  final bool enabled;
  final int daysBefore;
  final int hour;
  final int minute;

  static const builtInDefault = NotificationRule(scope: RuleScope.defaults);

  Map<String, Object?> toMap() => {
        'scope': scope.name,
        'targetId': targetId,
        'dateType': dateType?.name,
        'enabled': enabled,
        'daysBefore': daysBefore,
        'hour': hour,
        'minute': minute,
      };

  factory NotificationRule.fromMap(Map<String, Object?> m) => NotificationRule(
        scope: RuleScope.values.firstWhere((s) => s.name == m['scope'], orElse: () => RuleScope.defaults),
        targetId: m['targetId'] as String?,
        dateType: DateType.values.where((d) => d.name == m['dateType']).firstOrNull,
        enabled: (m['enabled'] as bool?) ?? true,
        daysBefore: (m['daysBefore'] as num?)?.toInt() ?? 2,
        hour: (m['hour'] as num?)?.toInt() ?? 9,
        minute: (m['minute'] as num?)?.toInt() ?? 0,
      );
}

class NotificationPrefs {
  const NotificationPrefs({
    this.itemNotifications = true,
    this.morningDigest = false,
    this.digestHour = 7,
    this.digestMinute = 30,
  });

  final bool itemNotifications;
  final bool morningDigest;
  final int digestHour;
  final int digestMinute;
}

/// Picks the rule that applies to [item]. Within a scope, a rule for the
/// item's specific date type beats a rule for both types.
NotificationRule resolveRule(PantryItem item, List<NotificationRule> rules) {
  NotificationRule? pick(RuleScope scope, bool Function(NotificationRule) target) {
    final matching = rules.where((r) =>
        r.scope == scope && target(r) && (r.dateType == null || r.dateType == item.dateType));
    return matching.where((r) => r.dateType != null).firstOrNull ?? matching.firstOrNull;
  }

  return pick(RuleScope.product, (r) => r.targetId == item.id || (item.ean != null && r.targetId == item.ean)) ??
      pick(RuleScope.category, (r) => r.targetId == item.categoryId) ??
      pick(RuleScope.defaults, (_) => true) ??
      NotificationRule.builtInDefault;
}

enum PlannedKind { item, digest }

class PlannedNotification {
  const PlannedNotification({required this.id, required this.at, required this.kind, required this.itemIds});

  /// Stable 31-bit id for the local notification plugin.
  final int id;
  final DateTime at;
  final PlannedKind kind;
  final List<String> itemIds;

  @override
  String toString() => 'Planned($kind, $at, $itemIds)';
}

/// Stable, platform-independent hash (FNV-1a) → positive 31-bit int.
int stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x3fffffff; // keep clear of the digest id range
}

const _digestIdBase = 0x40000000;

/// Computes every notification to schedule in the next [horizonDays].
List<PlannedNotification> planNotifications({
  required Iterable<PantryItem> items,
  required List<NotificationRule> rules,
  required NotificationPrefs prefs,
  required DateTime now,
  int horizonDays = 30,
  int digestDays = 7,
}) {
  final out = <PlannedNotification>[];
  final active = items.where((i) => i.status == ItemStatus.active).toList();
  final horizon = now.add(Duration(days: horizonDays));

  if (prefs.itemNotifications) {
    for (final item in active) {
      final rule = resolveRule(item, rules);
      if (!rule.enabled) continue;
      final day = dateOnly(item.expiryDate).subtract(Duration(days: rule.daysBefore));
      final at = DateTime(day.year, day.month, day.day, rule.hour, rule.minute);
      if (at.isAfter(now) && at.isBefore(horizon)) {
        out.add(PlannedNotification(id: stableId(item.id), at: at, kind: PlannedKind.item, itemIds: [item.id]));
      }
    }
  }

  if (prefs.morningDigest) {
    final today = dateOnly(now);
    for (var d = 0; d < digestDays; d++) {
      final day = today.add(Duration(days: d));
      final at = DateTime(day.year, day.month, day.day, prefs.digestHour, prefs.digestMinute);
      if (!at.isAfter(now)) continue;
      final due = active.where((i) {
        final rule = resolveRule(i, rules);
        return rule.enabled && daysLeft(i.expiryDate, day) <= rule.daysBefore;
      }).map((i) => i.id).toList();
      if (due.isNotEmpty) {
        out.add(PlannedNotification(
            id: _digestIdBase + day.difference(DateTime(2020)).inDays % 100000,
            at: at,
            kind: PlannedKind.digest,
            itemIds: due));
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
