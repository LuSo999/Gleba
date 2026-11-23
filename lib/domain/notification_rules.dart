/// Layered notification rules: default → category → product.
/// The server (functions/src/planner.ts) evaluates them and sends push
/// notifications; the app only edits them.
/// The most specific enabled-or-disabled rule wins, so a user can e.g. turn
/// notifications off for "drinks" but keep them on for one particular juice.
library;

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
    this.label,
  });

  final RuleScope scope;

  /// Human-readable name of the target (product name) for the settings list.
  final String? label;

  /// Category id for [RuleScope.category], item id or EAN for [RuleScope.product].
  final String? targetId;

  /// When set, applies only to items with this date type.
  final DateType? dateType;
  final bool enabled;
  final int daysBefore;
  final int hour;
  final int minute;

  static const builtInDefault = NotificationRule(scope: RuleScope.defaults);

  /// Stable document id: one rule per scope + target + date type.
  String get key => [scope.name, targetId ?? '-', dateType?.name ?? 'any'].join('_');

  NotificationRule copyWith({bool? enabled, int? daysBefore, int? hour, int? minute}) => NotificationRule(
        scope: scope,
        targetId: targetId,
        dateType: dateType,
        label: label,
        enabled: enabled ?? this.enabled,
        daysBefore: daysBefore ?? this.daysBefore,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Map<String, Object?> toMap() => {
        'scope': scope.name,
        'targetId': targetId,
        'dateType': dateType?.name,
        'enabled': enabled,
        'daysBefore': daysBefore,
        'hour': hour,
        'minute': minute,
        'label': label,
      };

  factory NotificationRule.fromMap(Map<String, Object?> m) => NotificationRule(
        scope: RuleScope.values.firstWhere((s) => s.name == m['scope'], orElse: () => RuleScope.defaults),
        targetId: m['targetId'] as String?,
        dateType: DateType.values.where((d) => d.name == m['dateType']).firstOrNull,
        enabled: (m['enabled'] as bool?) ?? true,
        daysBefore: (m['daysBefore'] as num?)?.toInt() ?? 2,
        hour: (m['hour'] as num?)?.toInt() ?? 9,
        minute: (m['minute'] as num?)?.toInt() ?? 0,
        label: m['label'] as String?,
      );
}

class NotificationPrefs {
  const NotificationPrefs({
    this.itemNotifications = true,
    this.morningDigest = false,
    this.digestHour = 7,
    this.digestMinute = 30,
    this.repeatExpired = true,
    this.othersActivity = false,
    this.quietEnabled = false,
    this.quietFrom = 22 * 60,
    this.quietTo = 7 * 60,
  });

  final bool itemNotifications;
  final bool morningDigest;
  final int digestHour;
  final int digestMinute;

  /// Remind about expired items every day until they are dealt with.
  final bool repeatExpired;

  /// Summary of what other household members added / ate / threw away.
  final bool othersActivity;

  /// Global "do not disturb"; times are minutes since midnight.
  final bool quietEnabled;
  final int quietFrom;
  final int quietTo;

  NotificationPrefs copyWith({
    bool? itemNotifications,
    bool? morningDigest,
    int? digestHour,
    int? digestMinute,
    bool? repeatExpired,
    bool? othersActivity,
    bool? quietEnabled,
    int? quietFrom,
    int? quietTo,
  }) =>
      NotificationPrefs(
        itemNotifications: itemNotifications ?? this.itemNotifications,
        morningDigest: morningDigest ?? this.morningDigest,
        digestHour: digestHour ?? this.digestHour,
        digestMinute: digestMinute ?? this.digestMinute,
        repeatExpired: repeatExpired ?? this.repeatExpired,
        othersActivity: othersActivity ?? this.othersActivity,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietFrom: quietFrom ?? this.quietFrom,
        quietTo: quietTo ?? this.quietTo,
      );

  /// Field names are shared with the server (functions/src/planner.ts).
  Map<String, Object?> toMap() => {
        'itemNotifications': itemNotifications,
        'morningDigest': morningDigest,
        'digestHour': digestHour,
        'digestMinute': digestMinute,
        'repeatExpired': repeatExpired,
        'othersActivity': othersActivity,
        'quietEnabled': quietEnabled,
        'quietFrom': quietFrom,
        'quietTo': quietTo,
      };

  factory NotificationPrefs.fromMap(Map<String, Object?>? m) {
    if (m == null) return const NotificationPrefs();
    int i(String k, int d) => (m[k] as num?)?.toInt() ?? d;
    bool b(String k, bool d) => (m[k] as bool?) ?? d;
    return NotificationPrefs(
      itemNotifications: b('itemNotifications', true),
      morningDigest: b('morningDigest', false),
      digestHour: i('digestHour', 7),
      digestMinute: i('digestMinute', 30),
      repeatExpired: b('repeatExpired', true),
      othersActivity: b('othersActivity', false),
      quietEnabled: b('quietEnabled', false),
      quietFrom: i('quietFrom', 22 * 60),
      quietTo: i('quietTo', 7 * 60),
    );
  }
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

/// Stable, platform-independent hash (FNV-1a) → positive 31-bit int.
int stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x3fffffff; // keep clear of the digest id range
}
