import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../theme.dart';
import 'burst.dart';

Future<void> finishWithFanfare(BuildContext context, WidgetRef ref, PantryItem item, ItemStatus how,
    {double? quantity}) async {
  final h = ref.read(activeHouseholdProvider);
  final user = ref.read(userProvider).value;
  if (h == null || user == null) return;
  final anim = ref.read(settingsProvider).animations;
  if (how == ItemStatus.consumed) {
    showBurst(context, '😋', particles: const ['✨', '💚', '⭐'], enabled: anim);
  } else {
    showBurst(context, '🗑️', particles: const ['💧'], enabled: anim);
  }
  await ref.read(repositoryProvider).finishItem(h.id, item, how, user.uid, quantity: quantity);
}

Future<void> showItemSheet(BuildContext context, PantryItem item) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(item: item),
    );

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.item});

  final PantryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final color = GlebaColors.freshness(freshnessOf(item, now), theme.brightness);
    final cat = categoryById(item.categoryId);
    final settings = ref.watch(settingsProvider);
    final repo = ref.read(repositoryProvider);
    final hid = ref.read(activeHouseholdProvider)?.id;
    final location = item.locationType ?? suggestLocation(item.categoryId);

    Future<void> update(PantryItem updated) async {
      if (hid != null) await repo.updateItem(hid, updated);
      if (context.mounted) Navigator.pop(context);
    }

    Future<void> finish(ItemStatus how, [double? q]) async {
      Navigator.pop(context);
      await finishWithFanfare(context, ref, item, how, quantity: q);
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
                    icon: const Text('😋'),
                    label: Text(l.eaten),
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
                    onPressed: () => update(item.copyWith(openedAt: now, expiryDate: expiryAfterOpening(item, now))),
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
                    )),
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
                    if (d != null) await update(item.copyWith(expiryDate: d));
                  },
                  icon: const Icon(Icons.edit_calendar),
                  label: Text(l.expiryDate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _qty(PantryItem i) =>
      '${i.quantity == i.quantity.roundToDouble() ? i.quantity.toInt() : i.quantity} ${i.unit}';
}
