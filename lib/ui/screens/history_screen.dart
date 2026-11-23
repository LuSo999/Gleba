import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/history.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';

/// Household history: what was added, eaten, thrown away… and by whom.
/// Eaten / thrown away items can be put back.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final events = ref.watch(historyProvider).value;
    final theme = Theme.of(context);
    if (events == null) return Scaffold(appBar: AppBar(title: Text(l.historyTitle)), body: const Center(child: CircularProgressIndicator()));

    // Removals that were already put back (a later "restored" event for the same item).
    final restoredAfter = <String>{};
    final seenRestore = <String>{};
    for (final e in events) {
      if (e.type == HistoryType.restored) seenRestore.add(e.itemId);
      if (e.isRemoval && seenRestore.contains(e.itemId)) restoredAfter.add(e.id);
    }

    final today = dateOnly(DateTime.now());
    String dayLabel(DateTime d) {
      final diff = today.difference(dateOnly(d)).inDays;
      if (diff == 0) return l.today;
      if (diff == 1) return l.yesterday;
      return formatDate(context, d);
    }

    final rows = <Widget>[];
    String? lastDay;
    for (final e in events) {
      final day = dayLabel(e.at);
      if (day != lastDay) {
        lastDay = day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(day, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      final (icon, label) = switch (e.type) {
        HistoryType.added => ('➕', l.histAdded),
        HistoryType.consumed => ('😋', l.histConsumed),
        HistoryType.discarded => ('🗑️', l.histDiscarded),
        HistoryType.opened => ('🔓', l.histOpened),
        HistoryType.frozen => ('❄️', l.histFrozen),
        HistoryType.edited => ('✏️', l.histEdited),
        HistoryType.restored => ('↩️', l.histRestored),
      };
      final qty = e.quantity == null
          ? ''
          : ' · ${e.quantity == e.quantity!.roundToDouble() ? e.quantity!.toInt() : e.quantity} ${e.unit ?? ''}';
      final time = TimeOfDay.fromDateTime(e.at).format(context);
      rows.add(ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Text(categoryById(e.categoryId).emoji, style: const TextStyle(fontSize: 28)),
            Positioned(right: -8, bottom: -6, child: Text(icon, style: const TextStyle(fontSize: 14))),
          ],
        ),
        title: Text(e.name),
        subtitle: Text('$label$qty · ${[if (e.byName?.isNotEmpty ?? false) e.byName!, time].join(' · ')}'),
        trailing: e.isRemoval && !restoredAfter.contains(e.id)
            ? TextButton(
                onPressed: () async {
                  final h = ref.read(activeHouseholdProvider);
                  final user = ref.read(userProvider).value;
                  if (h == null || user == null) return;
                  await ref.read(repositoryProvider).restoreFromHistory(h.id, e, user);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l.histRestored}: ${e.name}')));
                  }
                },
                child: Text(l.putBack),
              )
            : null,
      ));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.historyTitle)),
      body: events.isEmpty ? Center(child: Text(l.historyEmpty)) : ListView(children: rows),
    );
  }
}
