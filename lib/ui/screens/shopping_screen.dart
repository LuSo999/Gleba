import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/shelf_life.dart';
import '../../domain/shopping.dart';
import '../labels.dart';
import '../widgets/item_sheet.dart' show restock;

/// Shared shopping list. "2 mléko" adds two milks; ticked items move to
/// "Bought"; stock rules at the bottom refill the list automatically.
class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (text.isEmpty || h == null || user == null) return;
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(?:x|×|ks)?\s+(.+)$', caseSensitive: false).firstMatch(text);
    final name = m == null ? text : m[2]!.trim();
    final qty = m == null ? null : double.tryParse(m[1]!.replaceAll(',', '.'));
    _input.clear();
    await ref.read(repositoryProvider).addShopping(
          h.id,
          ShoppingEntry(id: '', name: name, quantity: qty, unit: qty == null ? null : 'ks',
              categoryId: guessCategory(name: name).id, productKey: nameKey(name)),
          user,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final h = ref.watch(activeHouseholdProvider);
    final list = ref.watch(shoppingListProvider).value ?? const [];
    final rules = ref.watch(stockRulesProvider).value ?? const [];
    final items = ref.watch(itemsProvider).value ?? const [];
    final repo = ref.read(repositoryProvider);
    final order = {for (final (i, c) in foodCategories.indexed) c.id: i};
    int byCategory(ShoppingEntry a, ShoppingEntry b) {
      final c = (order[a.categoryId] ?? 99).compareTo(order[b.categoryId] ?? 99);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    final open = list.where((e) => !e.done).toList()..sort(byCategory);
    final bought = list.where((e) => e.done).toList()..sort(byCategory);

    Widget tile(ShoppingEntry e) => Dismissible(
          key: ValueKey(e.id),
          onDismissed: (_) => repo.deleteShopping(h!.id, e.id),
          background: Container(color: theme.colorScheme.errorContainer),
          child: CheckboxListTile(
            value: e.done,
            onChanged: (v) => repo.setShoppingDone(h!.id, e.id, v ?? false),
            secondary: Text(categoryById(e.categoryId).emoji, style: const TextStyle(fontSize: 24)),
            title: Text(
              e.quantity == null ? e.name : '${e.name} · ${_q(e.quantity!)} ${e.unit ?? ''}',
              style: e.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
            ),
            subtitle: Text([if (e.auto) '🔁 ${l.stockAuto}', if (e.byName?.isNotEmpty ?? false) e.byName!].join(' · ')),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.shoppingTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.shoppingAdd, isDense: true),
                  onSubmitted: (_) => _add(),
                ),
              ),
              IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
            ]),
          ),
          if (open.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l.shoppingEmpty))),
          ...open.map(tile),
          if (bought.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(children: [
                Text(l.shoppingBought, style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton(onPressed: () => repo.clearBought(h!.id), child: Text(l.shoppingClear)),
              ]),
            ),
            ...bought.map(tile),
          ],
          if (rules.isNotEmpty) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('🔁 ${l.stockRules}', style: theme.textTheme.titleSmall),
            ),
            for (final r in rules)
              ListTile(
                leading: Text(categoryById(r.categoryId).emoji, style: const TextStyle(fontSize: 24)),
                title: Text(r.name),
                subtitle: Text('${l.stockMin} ${_q(r.minQuantity)} ${r.unit} · '
                    '${l.stockNow('${_q(stockOf(r.productKey, items))} ${r.unit}')}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => repo.deleteStockRule(h!.id, r.productKey),
                ),
                onTap: () => editStockRule(context, ref, r),
              ),
          ],
        ],
      ),
    );
  }

  static String _q(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

/// Dialog for "always have at least N"; saves the rule and refills the list
/// right away if the stock is already low.
Future<void> editStockRule(BuildContext context, WidgetRef ref, StockRule rule) async {
  // Read everything up front: the caller (e.g. a closing bottom sheet) may be
  // gone by the time the dialog returns.
  final h = ref.read(activeHouseholdProvider);
  final user = ref.read(userProvider).value;
  final repo = ref.read(repositoryProvider);
  if (h == null || user == null) return;
  final l = context.l;
  var min = rule.minQuantity;
  final save = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('🔁 ${rule.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.stockMin),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: min > 1 ? () => setState(() => min--) : null),
            Text('${min.toInt()} ${rule.unit}', style: Theme.of(ctx).textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => min++)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.save)),
        ],
      ),
    ),
  );
  if (save != true) return;
  final updated = StockRule(
      productKey: rule.productKey, name: rule.name, minQuantity: min, unit: rule.unit, categoryId: rule.categoryId);
  await repo.saveStockRule(h.id, updated);
  await restock(repo, h.id, user, rules: [updated]);
}
