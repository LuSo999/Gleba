import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../data/repository.dart';
import '../../domain/freshness.dart';
import '../../domain/history.dart';
import '../../domain/models.dart';
import '../../domain/notification_rules.dart';
import '../../domain/shelf_life.dart';
import '../../l10n/app_localizations.dart';
import '../labels.dart';
import '../theme.dart';
import 'burst.dart';

/// Item actions with an "Undo" snackbar. Everything needed is captured up
/// front, so the actions keep working after the bottom sheet is closed.
class ItemActions {
  ItemActions._(this._repo, this._hid, this._user, this._anim, this._overlay, this._messenger, this._l);

  static ItemActions? of(BuildContext host, WidgetRef ref) {
    final hid = ref.read(activeHouseholdProvider)?.id;
    final user = ref.read(userProvider).value;
    if (hid == null || user == null) return null;
    return ItemActions._(ref.read(repositoryProvider), hid, user, ref.read(settingsProvider).animations,
        Overlay.maybeOf(host, rootOverlay: true), ScaffoldMessenger.maybeOf(host), AppLocalizations.of(host));
  }

  final GlebaRepository _repo;
  final String _hid;
  final GlebaUser _user;
  final bool _anim;
  final OverlayState? _overlay;
  final ScaffoldMessengerState? _messenger;
  final AppLocalizations _l;

  void _snack(String text, Future<void> Function() undo) {
    _messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(label: _l.undo, onPressed: () => undo()),
      ));
  }

  Future<void> finish(PantryItem item, ItemStatus how, {double? quantity}) async {
    how == ItemStatus.consumed
        ? showBurstOn(_overlay, '😋', particles: const ['✨', '💚', '⭐'], enabled: _anim)
        : showBurstOn(_overlay, '🗑️', particles: const ['💧'], enabled: _anim);
    final eventId = await _repo.finishItem(_hid, item, how, _user, quantity: quantity);
    final label = quantity != null && quantity < item.quantity ? '${item.name} (${_fmt(quantity)} ${item.unit})' : item.name;
    _snack(how == ItemStatus.consumed ? _l.snackConsumed(label) : _l.snackDiscarded(label),
        () => _repo.undoFinish(_hid, item, eventId));
  }

  Future<void> change(PantryItem original, PantryItem updated, HistoryType type) async {
    await _repo.updateItem(_hid, updated, history: type, by: _user);
    _snack(_l.snackChanged(original.name), () => _repo.updateItem(_hid, original));
  }

  static String _fmt(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

Future<void> finishWithFanfare(BuildContext context, WidgetRef ref, PantryItem item, ItemStatus how,
        {double? quantity}) async =>
    ItemActions.of(context, ref)?.finish(item, how, quantity: quantity);

Future<void> showItemSheet(BuildContext context, WidgetRef ref, PantryItem item) {
  final actions = ItemActions.of(context, ref);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ItemSheet(item: item, actions: actions),
  );
}

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.item, required this.actions});

  final PantryItem item;

  /// Captured when the sheet was opened, so it survives the list row being
  /// removed while the sheet closes.
  final ItemActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final color = GlebaColors.freshness(freshnessOf(item, now), theme.brightness);
    final cat = categoryById(item.categoryId);
    final settings = ref.watch(settingsProvider);
    final location = item.locationType ?? suggestLocation(item.categoryId);

    Future<void> update(PantryItem updated, HistoryType type) async {
      if (context.mounted) Navigator.pop(context);
      await actions?.change(item, updated, type);
    }

    Future<void> finish(ItemStatus how, [double? q]) async {
      Navigator.pop(context);
      await actions?.finish(item, how, quantity: q);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 44)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: theme.textTheme.titleLarge),
                      Text(
                        [if (item.brand != null) item.brand!, categoryLabel(l, item.categoryId)].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(Icons.event, color: color, size: 18),
                  label: Text('${dateTypeLabel(l, item.dateType)}: ${formatDate(context, item.expiryDate)} '
                      '(${relativeExpiry(l, item.expiryDate, now)})'),
                  side: BorderSide(color: color),
                ),
                Chip(label: Text('${locationLabel(l, location)} · ${_qty(item)}')),
                if (item.isOpened) Chip(avatar: const Text('🔓'), label: Text(l.opened)),
                if (item.isFrozen)
                  Chip(avatar: const Text('❄️'), label: Text(l.frozenSince(formatDate(context, item.frozenAt!)))),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => finish(ItemStatus.consumed),
                    icon: Text(cat.multiUse ? '✅' : '😋'),
                    label: Text(cat.multiUse ? l.usedUp : l.eaten),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => finish(ItemStatus.discarded),
                    icon: const Text('🗑️'),
                    label: Text(l.discarded),
                  ),
                ),
              ],
            ),
            if (settings.partialConsumption && item.quantity > 1 && item.unit == 'ks') ...[
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: () => finish(ItemStatus.consumed, 1), child: Text(l.eatOne)),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                if (!item.isOpened)
                  TextButton.icon(
                    onPressed: () => update(item.copyWith(openedAt: now, expiryDate: expiryAfterOpening(item, now)), HistoryType.opened),
                    icon: const Text('🔓'),
                    label: Text(l.markOpened),
                  ),
                if (!item.isFrozen && location != LocationType.freezer)
                  TextButton.icon(
                    onPressed: () => update(item.copyWith(
                      frozenAt: now,
                      expiryDate: expiryAfterFreezing(item, now),
                      locationType: LocationType.freezer,
                      locationId: LocationType.freezer.name,
                    ), HistoryType.frozen),
                    icon: const Text('❄️'),
                    label: Text(l.freeze),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: item.expiryDate,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now.add(const Duration(days: 365 * 5)),
                    );
                    if (d != null) await update(item.copyWith(expiryDate: d), HistoryType.edited);
                  },
                  icon: const Icon(Icons.edit_calendar),
                  label: Text(l.expiryDate),
                ),
                TextButton.icon(
                  onPressed: () => _editProductRule(context, ref, item),
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(l.notifications),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Per-product exception, keyed by EAN (so it applies to future purchases
  /// too) or by the item id for products without a barcode.
  static Future<void> _editProductRule(BuildContext context, WidgetRef ref, PantryItem item) async {
    final l = context.l;
    final user = ref.read(userProvider).value;
    if (user == null) return;
    final repo = ref.read(repositoryProvider);
    final target = item.ean ?? item.id;
    final current = (ref.read(notificationRulesProvider).value ?? const [])
        .where((r) => r.scope == RuleScope.product && r.targetId == target)
        .firstOrNull;
    // -1 = use default, -2 = off, n >= 0 = n days before
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.notificationForProduct),
        children: [
          for (final (value, label) in [
            (-1, l.useDefault),
            (-2, l.off),
            for (final d in [0, 1, 2, 3, 5, 7]) (d, l.daysBefore(d)),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, value),
              child: Row(children: [
                Icon(
                  (value == -1 && current == null) ||
                          (value == -2 && current?.enabled == false) ||
                          (current?.enabled == true && current?.daysBefore == value)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(label),
              ]),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final rule = NotificationRule(
      scope: RuleScope.product,
      targetId: target,
      label: item.name,
      enabled: choice != -2,
      daysBefore: choice >= 0 ? choice : (current?.daysBefore ?? 2),
      hour: current?.hour ?? 9,
      minute: current?.minute ?? 0,
    );
    choice == -1 ? await repo.deleteNotificationRule(user.uid, rule) : await repo.saveNotificationRule(user.uid, rule);
  }

  static String _qty(PantryItem i) =>
      '${i.quantity == i.quantity.roundToDouble() ? i.quantity.toInt() : i.quantity} ${i.unit}';
}
