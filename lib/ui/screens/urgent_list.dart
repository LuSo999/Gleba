import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/freshness.dart';
import '../../domain/merge.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/item_sheet.dart';

/// "Eat first" – everything sorted by urgency. Swipe right = eaten,
/// swipe left = thrown away.
class UrgentList extends ConsumerWidget {
  const UrgentList({super.key, required this.items});

  final List<PantryItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = DateTime.now();
    final sorted = groupSameNames(sortByUrgency(items, now));
    if (sorted.isEmpty) return Center(child: Text(l.nothingUrgent));
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final item = sorted[i];
        final color = GlebaColors.freshness(freshnessOf(item, now), theme.brightness);
        return Dismissible(
          key: ValueKey(item.id),
          background: _swipeBg(context, l.eaten, '😋', Alignment.centerLeft, Colors.green),
          secondaryBackground: _swipeBg(context, l.discarded, '🗑️', Alignment.centerRight, Colors.red),
          confirmDismiss: (dir) async {
            await finishWithFanfare(
                context, ref, item, dir == DismissDirection.startToEnd ? ItemStatus.consumed : ItemStatus.discarded);
            return true;
          },
          child: ListTile(
            onTap: () => showItemSheet(context, ref, item),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.18),
              child: Text(categoryById(item.categoryId).emoji, style: const TextStyle(fontSize: 20)),
            ),
            title: Text(item.name),
            subtitle: Text(
              '${relativeExpiry(l, item.expiryDate, now)} · ${dateTypeLabel(l, item.dateType)}'
              '${item.quantity > 1 ? ' · ${item.quantity.round()} ${item.unit}' : ''}',
              style: TextStyle(color: color),
            ),
            trailing: Container(width: 6, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          ),
        );
      },
    );
  }

  Widget _swipeBg(BuildContext context, String label, String emoji, Alignment align, Color color) => Container(
        color: color.withValues(alpha: 0.15),
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('$emoji  $label', style: Theme.of(context).textTheme.titleMedium),
      );
}
