import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../domain/notification_rules.dart';
import '../../domain/shelf_life.dart';
import '../../services/notification_service.dart';
import '../labels.dart';

/// Every user has their own notification settings:
/// defaults (per date type) → category exceptions → product exceptions.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final user = ref.watch(userProvider).value;
    final prefs = ref.watch(notificationPrefsProvider).value ?? const NotificationPrefs();
    final rules = ref.watch(notificationRulesProvider).value ?? const [];
    final repo = ref.read(repositoryProvider);
    if (user == null) return const Scaffold();

    void savePrefs(NotificationPrefs p) => repo.saveNotificationPrefs(user.uid, p);
    void saveRule(NotificationRule r) => repo.saveNotificationRule(user.uid, r);

    NotificationRule defaultFor(DateType t) =>
        rules.where((r) => r.scope == RuleScope.defaults && r.dateType == t).firstOrNull ??
        NotificationRule(scope: RuleScope.defaults, dateType: t);

    final categoryRules = rules.where((r) => r.scope == RuleScope.category).toList();
    final productRules = rules.where((r) => r.scope == RuleScope.product).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.notifications)),
      body: ListView(
        children: [
          if (!NotificationService.supported)
            Card(
              margin: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(l.notificationsAndroidOnly)),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l.itemNotifications),
            value: prefs.itemNotifications,
            onChanged: (v) => savePrefs(prefs.copyWith(itemNotifications: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_twilight),
            title: Text(l.morningDigest),
            subtitle: Text(l.morningDigestText),
            value: prefs.morningDigest,
            onChanged: (v) => savePrefs(prefs.copyWith(morningDigest: v)),
          ),
          if (prefs.morningDigest)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: Text(l.time),
              trailing: _TimeButton(
                hour: prefs.digestHour,
                minute: prefs.digestMinute,
                onChanged: (t) => savePrefs(prefs.copyWith(digestHour: t.hour, digestMinute: t.minute)),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.replay),
            title: Text(l.repeatExpired),
            subtitle: Text(l.repeatExpiredText),
            value: prefs.repeatExpired,
            onChanged: (v) => savePrefs(prefs.copyWith(repeatExpired: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.groups_outlined),
            title: Text(l.othersActivity),
            subtitle: Text(l.othersActivityText),
            value: prefs.othersActivity,
            onChanged: (v) => savePrefs(prefs.copyWith(othersActivity: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined),
            title: Text(l.quietHours),
            subtitle: prefs.quietEnabled
                ? Text('${_fmt(context, prefs.quietFrom)} – ${_fmt(context, prefs.quietTo)}')
                : null,
            value: prefs.quietEnabled,
            onChanged: (v) => savePrefs(prefs.copyWith(quietEnabled: v)),
          ),
          if (prefs.quietEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l.from),
                  _TimeButton(
                    hour: prefs.quietFrom ~/ 60,
                    minute: prefs.quietFrom % 60,
                    onChanged: (t) => savePrefs(prefs.copyWith(quietFrom: t.hour * 60 + t.minute)),
                  ),
                  Text(l.to),
                  _TimeButton(
                    hour: prefs.quietTo ~/ 60,
                    minute: prefs.quietTo % 60,
                    onChanged: (t) => savePrefs(prefs.copyWith(quietTo: t.hour * 60 + t.minute)),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Text('📋', style: TextStyle(fontSize: 22)),
            title: Text(l.inventoryReminder),
            subtitle: Text(l.inventoryReminderText),
            value: prefs.inventoryReminder,
            onChanged: (v) => savePrefs(prefs.copyWith(inventoryReminder: v)),
          ),
          if (prefs.inventoryReminder)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                DropdownButton<int>(
                  value: prefs.inventoryWeekday,
                  onChanged: (v) => savePrefs(prefs.copyWith(inventoryWeekday: v)),
                  items: [
                    for (var d = 1; d <= 7; d++)
                      DropdownMenuItem(
                        value: d,
                        // Material's narrow weekday names start on Sunday (index 0).
                        child: Text(MaterialLocalizations.of(context).narrowWeekdays[d % 7]),
                      ),
                  ],
                ),
                _TimeButton(
                  hour: prefs.inventoryMinutes ~/ 60,
                  minute: prefs.inventoryMinutes % 60,
                  onChanged: (t) => savePrefs(prefs.copyWith(inventoryMinutes: t.hour * 60 + t.minute)),
                ),
              ]),
            ),
          _Header(l.defaultsSection),
          for (final t in DateType.values)
            _RuleTile(
              title: dateTypeLabel(l, t),
              leading: Icon(t == DateType.useBy ? Icons.warning_amber : Icons.event_available),
              rule: defaultFor(t),
              onChanged: saveRule,
            ),
          _Header(l.categoryExceptions),
          for (final r in categoryRules)
            _RuleTile(
              title: categoryLabel(l, r.targetId ?? ''),
              leading: Text(categoryById(r.targetId).emoji, style: const TextStyle(fontSize: 22)),
              rule: r,
              onChanged: saveRule,
              onDelete: () => repo.deleteNotificationRule(user.uid, r),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.addCategoryException),
            onTap: () async {
              final id = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(l.category),
                  children: [
                    for (final c in foodCategories.where((c) => !categoryRules.any((r) => r.targetId == c.id)))
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, c.id),
                        child: Text('${c.emoji}  ${categoryLabel(l, c.id)}'),
                      ),
                  ],
                ),
              );
              if (id != null) saveRule(NotificationRule(scope: RuleScope.category, targetId: id));
            },
          ),
          if (productRules.isNotEmpty) ...[
            _Header(l.productExceptions),
            for (final r in productRules)
              _RuleTile(
                title: r.label ?? r.targetId ?? '',
                leading: const Icon(Icons.inventory_2_outlined),
                rule: r,
                onChanged: saveRule,
                onDelete: () => repo.deleteNotificationRule(user.uid, r),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

String _fmt(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// One rule: on/off, how many days before, at what time.
class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.title, required this.leading, required this.rule, required this.onChanged, this.onDelete});

  final String title;
  final Widget leading;
  final NotificationRule rule;
  final ValueChanged<NotificationRule> onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      children: [
        SwitchListTile(
          secondary: leading,
          title: Text(title),
          subtitle: Text(rule.enabled
              ? '${l.daysBefore(rule.daysBefore)}, ${TimeOfDay(hour: rule.hour, minute: rule.minute).format(context)}'
              : l.off),
          value: rule.enabled,
          onChanged: (v) => onChanged(rule.copyWith(enabled: v)),
        ),
        if (rule.enabled)
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: rule.daysBefore > 0 ? () => onChanged(rule.copyWith(daysBefore: rule.daysBefore - 1)) : null,
                ),
                Text('${rule.daysBefore}'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: rule.daysBefore < 14 ? () => onChanged(rule.copyWith(daysBefore: rule.daysBefore + 1)) : null,
                ),
                const Spacer(),
                _TimeButton(
                  hour: rule.hour,
                  minute: rule.minute,
                  onChanged: (t) => onChanged(rule.copyWith(hour: t.hour, minute: t.minute)),
                ),
                if (onDelete != null) IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: onDelete),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.hour, required this.minute, required this.onChanged});

  final int hour;
  final int minute;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = TimeOfDay(hour: hour, minute: minute);
    return OutlinedButton.icon(
      icon: const Icon(Icons.schedule, size: 18),
      label: Text(t.format(context)),
      onPressed: () async {
        final picked = await showTimePicker(context: context, initialTime: t);
        if (picked != null) onChanged(picked);
      },
    );
  }
}
