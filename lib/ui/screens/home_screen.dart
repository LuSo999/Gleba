import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../fridge/fridge_view.dart';
import '../labels.dart';
import '../widgets/item_sheet.dart';
import 'households_screen.dart';
import 'urgent_list.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _list = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final households = ref.watch(householdsProvider);
    final active = ref.watch(activeHouseholdProvider);
    final items = ref.watch(itemsProvider).value ?? const [];
    final isDemo = ref.watch(isDemoProvider);

    if (households.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (active == null) return const NoHouseholdScreen();

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: l.households,
          onSelected: (id) => id == '_manage'
              ? context.push('/households')
              : ref.read(activeHouseholdIdProvider.notifier).select(id),
          itemBuilder: (_) => [
            for (final h in households.value ?? const [])
              CheckedPopupMenuItem(value: h.id, checked: h.id == active.id, child: Text(h.name)),
            const PopupMenuDivider(),
            PopupMenuItem(value: '_manage', child: Text(l.households)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(active.name), const Icon(Icons.arrow_drop_down)],
          ),
        ),
        actions: [
          IconButton(
            tooltip: l.invite,
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => showInviteDialog(context, ref, active),
          ),
          IconButton(
            tooltip: l.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isDemo ? 84 : 56),
          child: Column(
            children: [
              if (isDemo)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(l.demoBanner, style: Theme.of(context).textTheme.labelSmall),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(l.viewFridge), icon: const Text('🧊')),
                    ButtonSegment(value: true, label: Text(l.viewList), icon: const Icon(Icons.schedule)),
                  ],
                  selected: {_list},
                  onSelectionChanged: (s) => setState(() => _list = s.first),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: ref.watch(settingsProvider).anim(const Duration(milliseconds: 250)),
        child: _list
            ? UrgentList(key: const ValueKey('list'), items: items)
            : FridgeView(key: const ValueKey('fridge'), items: items, onItemTap: (i) => showItemSheet(context, i)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMenu(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(l.addItem),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    final l = context.l;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(l.scanBarcode),
              onTap: () => _go(ctx, '/add?mode=scan'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(l.enterManually),
              onTap: () => _go(ctx, '/add?mode=manual'),
            ),
            ListTile(
              leading: const Text('🍲', style: TextStyle(fontSize: 22)),
              title: Text(l.addLeftover),
              onTap: () => _go(ctx, '/add?mode=leftover'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('🧾'),
              subtitle: Text(l.comingSoon),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext sheetContext, String path) {
    Navigator.pop(sheetContext);
    context.push(path);
  }
}
