import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../fridge/fridge_view.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/item_sheet.dart';
import 'households_screen.dart';
import 'shopping_screen.dart';
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
    ref.watch(householdUpkeepProvider);
    final households = ref.watch(householdsProvider);
    final active = ref.watch(activeHouseholdProvider);
    final items = ref.watch(itemsProvider).value ?? const [];
    final isDemo = ref.watch(isDemoProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final extraWide = width >= 1350;
    final now = DateTime.now();
    final longExpired = items.where((i) => daysLeft(i.expiryDate, now) < -3).length;
    final shoppingCount = (ref.watch(shoppingListProvider).value ?? const []).where((e) => !e.done).length;

    if (households.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (active == null) return const NoHouseholdScreen();

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: l.households,
          onSelected: (id) =>
              id == '_manage' ? context.push('/households') : ref.read(activeHouseholdIdProvider.notifier).select(id),
          itemBuilder: (_) => [
            for (final h in households.value ?? const [])
              CheckedPopupMenuItem(value: h.id, checked: h.id == active.id, child: Text(h.name)),
            const PopupMenuDivider(),
            PopupMenuItem(value: '_manage', child: Text(l.households)),
          ],
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(active.name), const Icon(Icons.arrow_drop_down)]),
        ),
        actions: [
          IconButton(
            tooltip: l.shoppingTitle,
            icon: Badge(
              isLabelVisible: shoppingCount > 0,
              label: Text('$shoppingCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: () => context.push('/shopping'),
          ),
          IconButton(
            tooltip: l.recipesTitle,
            icon: const Icon(Icons.restaurant_menu),
            onPressed: () => context.push('/recipes'),
          ),
          PopupMenuButton<String>(
            tooltip: l.more,
            onSelected: (v) => switch (v) {
              'history' => context.push('/history'),
              'stats' => context.push('/stats'),
              'inventory' => context.push('/inventory'),
              'plan' => context.push('/plan'),
              'invite' => showInviteDialog(context, ref, active),
              _ => context.push('/settings'),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'history',
                child: ListTile(leading: const Icon(Icons.history), title: Text(l.historyTitle)),
              ),
              PopupMenuItem(
                value: 'inventory',
                child: ListTile(
                  leading: const Text('📋', style: TextStyle(fontSize: 20)),
                  title: Text(l.inventoryTitle),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(leading: const Icon(Icons.insights), title: Text(l.statsTitle)),
              ),
              PopupMenuItem(
                value: 'invite',
                child: ListTile(leading: const Icon(Icons.person_add_alt), title: Text(l.invite)),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(leading: const Icon(Icons.settings_outlined), title: Text(l.settings)),
              ),
            ],
          ),
        ],
        // On wide screens fridge and list are side by side – no switch needed.
        bottom: wide
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
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
              ),
      ),
      body: Column(
        children: [
          // Kept out of the AppBar so long text can never squash the toolbar.
          if (isDemo && !const bool.fromEnvironment('GLEBA_DEMO'))
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(l.demoBanner, style: Theme.of(context).textTheme.labelSmall),
            ),
          if (longExpired > 0)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    const Text('⏰ '),
                    Expanded(child: Text(l.invLongExpired(longExpired), style: Theme.of(context).textTheme.bodySmall)),
                    TextButton(onPressed: () => context.push('/inventory?filter=expired'), child: Text(l.invCheck)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Material(
                          color: GlebaColors.backdrop(Theme.of(context).brightness),
                          child: FridgeView(items: items, onItemTap: (i) => showItemSheet(context, ref, i)),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 400,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule, size: 20),
                                  const SizedBox(width: 8),
                                  Text(l.viewList, style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            ),
                            Expanded(child: UrgentList(items: items)),
                          ],
                        ),
                      ),
                      if (extraWide) ...[
                        const VerticalDivider(width: 1),
                        const SizedBox(width: 380, child: ShoppingScreen(embedded: true)),
                      ],
                    ],
                  )
                : Material(
                    // Soft purple tint behind the fridge, matching the app icon.
                    color: GlebaColors.backdrop(Theme.of(context).brightness),
                    child: AnimatedSwitcher(
                      duration: ref.watch(settingsProvider).anim(const Duration(milliseconds: 250)),
                      child: _list
                          ? UrgentList(key: const ValueKey('list'), items: items)
                          : FridgeView(
                              key: const ValueKey('fridge'),
                              items: items,
                              onItemTap: (i) => showItemSheet(context, ref, i),
                            ),
                    ),
                  ),
          ),
        ],
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
              title: Text(l.receiptTitle),
              onTap: () => _go(ctx, '/receipt'),
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
