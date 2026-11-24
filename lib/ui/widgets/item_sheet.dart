import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../data/repository.dart';
import '../../domain/eaters.dart';
import '../../domain/freshness.dart';
import '../../domain/history.dart';
import '../../domain/models.dart';
import '../../domain/notification_rules.dart';
import '../../domain/shelf_life.dart';
import '../../domain/shopping.dart';
import '../../services/health_service.dart';
import '../../app.dart' show rootNavigatorKey;
import '../../l10n/app_localizations.dart';
import '../labels.dart';
import '../theme.dart';
import '../screens/shopping_screen.dart';
import 'burst.dart';
import 'edit_item_sheet.dart';
import 'who_ate_sheet.dart';

/// Adds products that dropped below their stock rule to the shopping list.
Future<void> restock(GlebaRepository repo, String hid, GlebaUser by, {List<StockRule>? rules}) async {
  final r = rules ?? await repo.watchStockRules(hid).first;
  if (r.isEmpty) return;
  final items = await repo.watchActiveItems(hid).first;
  final list = await repo.watchShoppingList(hid).first;
  for (final rule in restockNeeded(r, items, list)) {
    final missing = rule.minQuantity - stockOf(rule.productKey, items);
    await repo.addShopping(
      hid,
      ShoppingEntry(
        id: '',
        name: rule.name,
        quantity: missing,
        unit: rule.unit,
        categoryId: rule.categoryId,
        productKey: rule.productKey,
        auto: true,
      ),
      by,
    );
  }
}

/// Item actions with an "Undo" snackbar. Everything needed is captured up
/// front, so the actions keep working after the bottom sheet is closed.
class ItemActions {
  ItemActions._(this._repo, this._household, this._user, this._anim, this._overlay, this._messenger, this._l,
      this._health, this._askWhoAte);

  static ItemActions? of(BuildContext host, WidgetRef ref) {
    final household = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (household == null || user == null) return null;
    return ItemActions._(
      ref.read(repositoryProvider),
      household,
      user,
      ref.read(settingsProvider).animations,
      Overlay.maybeOf(host, rootOverlay: true),
      ScaffoldMessenger.maybeOf(host),
      AppLocalizations.of(host),
      ref.read(settingsProvider).healthWrite && HealthService.supported,
      ref.read(settingsProvider).askWhoAte,
    );
  }

  final GlebaRepository _repo;
  final Household _household;
  String get _hid => _household.id;
  final bool _askWhoAte;
  final GlebaUser _user;
  final bool _anim;
  final OverlayState? _overlay;
  final ScaffoldMessengerState? _messenger;
  final AppLocalizations _l;
  final bool _health;

  void _snack(String text, Future<void> Function() undo) {
    _messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 6),
          persist: false,
          action: SnackBarAction(label: _l.undo, onPressed: () => undo()),
        ),
      );
  }

  /// Whether "Eaten" asks who ate it.
  bool get asksWhoAte => _askWhoAte && _household.memberIds.length > 1;

  /// null = the sheet was dismissed (cancel the action).
  Future<Map<String, double>?> _eaters(String title, double? grams) async {
    if (!asksWhoAte) return {_user.uid: 1.0};
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return {_user.uid: 1.0};
    return showWhoAteSheet(ctx, household: _household, myUid: _user.uid, title: title, grams: grams);
  }

  static double? _gramsOf(PantryItem item, double q) =>
      item.nutrition != null || const ['g', 'kg', 'ml', 'l'].contains(item.unit) ? gramsEaten(item, q) : null;

  Future<void> finish(PantryItem item, ItemStatus how, {double? quantity}) async {
    final eaten = how == ItemStatus.consumed;
    final q = quantity ?? item.quantity;
    Map<String, double>? eaters;
    if (eaten) {
      eaters = await _eaters(item.name, _gramsOf(item, q));
      if (eaters == null) return;
    }
    eaten
        ? showBurstOn(_overlay, '😋', particles: const ['✨', '💚', '⭐'], enabled: _anim)
        : showBurstOn(_overlay, '🗑️', particles: const ['💧'], enabled: _anim);
    final eventId = await _repo.finishItem(_hid, item, how, _user, quantity: quantity, eaters: eaters);
    await restock(_repo, _hid, _user);
    final label = quantity != null && quantity < item.quantity
        ? '${item.name} (${_fmt(quantity)} ${item.unit})'
        : item.name;
    _snack(
      eaten ? _l.snackConsumed(label) : _l.snackDiscarded(label),
      () => _repo.undoFinish(_hid, item, eventId),
    );
    if (eaten && _health && item.nutrition != null) {
      if (asksWhoAte) {
        // The split was just chosen: my share goes to Health right away; the
        // others' phones write theirs (HealthSync).
        final mine = eaters![_user.uid] ?? 0;
        if (mine > 0 && await HealthService.instance.writeEaten(item, gramsEaten(item, q) * mine)) {
          _messenger?.showSnackBar(SnackBar(content: Text(_l.healthWritten)));
        }
      } else {
        await _logToHealth(item, gramsEaten(item, q));
      }
    }
  }

  /// Several items eaten at once (bread + butter + ham + cheese).
  Future<void> finishMany(List<PantryItem> items, ItemStatus how) async {
    if (items.isEmpty) return;
    final eaten = how == ItemStatus.consumed;
    Map<String, double>? eaters;
    if (eaten) {
      final grams = items.map((i) => _gramsOf(i, i.quantity)).toList();
      eaters = await _eaters(
        items.map((i) => i.name).join(' + '),
        grams.contains(null) ? null : grams.fold<double>(0, (s, g) => s + g!),
      );
      if (eaters == null) return;
    }
    eaten
        ? showBurstOn(_overlay, '😋', particles: const ['✨', '💚', '⭐'], enabled: _anim)
        : showBurstOn(_overlay, '🗑️', particles: const ['💧'], enabled: _anim);
    final done = <(PantryItem, String)>[];
    for (final i in items) {
      done.add((i, await _repo.finishItem(_hid, i, how, _user, eaters: eaters)));
    }
    await restock(_repo, _hid, _user);
    _snack(eaten ? _l.snackConsumedMany(items.length) : _l.snackDiscardedMany(items.length), () async {
      for (final (i, e) in done) {
        await _repo.undoFinish(_hid, i, e);
      }
    });
    final mine = eaters?[_user.uid] ?? 0;
    if (eaten && _health && mine > 0) {
      var wrote = false;
      for (final i in items.where((i) => i.nutrition != null)) {
        wrote = await HealthService.instance.writeEaten(i, gramsEaten(i, i.quantity) * mine) || wrote;
      }
      if (wrote) _messenger?.showSnackBar(SnackBar(content: Text(_l.healthWritten)));
    }
  }

  /// Items added by mistake, all at once.
  Future<void> deleteMany(List<PantryItem> items) async {
    final done = <(PantryItem, String)>[];
    for (final i in items) {
      done.add((i, await _repo.deleteItem(_hid, i, _user)));
    }
    _snack(_l.snackDeletedMany(items.length), () async {
      for (final (i, e) in done) {
        await _repo.undoFinish(_hid, i, e);
      }
    });
  }

  /// Cooks [items] into one dish that goes to the fridge.
  Future<void> cook(List<PantryItem> items, String name) async {
    if (items.isEmpty) return;
    final now = DateTime.now();
    final meal = PantryItem(
      id: '',
      name: name,
      categoryId: 'leftovers',
      expiryDate: suggestExpiry('leftovers', LocationType.fridge, now),
      locationType: LocationType.fridge,
      locationId: LocationType.fridge.name,
      source: ItemSource.leftover,
      nutrition: cookedNutrition([for (final i in items) (i, gramsEaten(i, i.quantity))]),
      price: items.any((i) => i.price != null) ? items.fold<double>(0, (s, i) => s + (i.price ?? 0)) : null,
    );
    showBurstOn(_overlay, '🍲', particles: const ['✨', '🔥'], enabled: _anim);
    final res = await _repo.cookMeal(_hid, items, meal, _user);
    await restock(_repo, _hid, _user);
    _snack(_l.snackCooked(name, items.length), () => _repo.undoCook(_hid, items, res));
  }

  Future<void> setRunningLow(PantryItem item, bool v) => change(item, item.copyWith(runningLow: v), HistoryType.edited);

  /// "How much did you eat?" with a live preview, then Health Connect.
  Future<void> _logToHealth(PantryItem item, double grams) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final eaten = await showModalBottomSheet<double>(
      context: ctx,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HealthSheet(item: item, grams: grams),
    );
    if (eaten == null || eaten <= 0) return;
    if (await HealthService.instance.writeEaten(item, eaten)) {
      _messenger?.showSnackBar(SnackBar(content: Text(_l.healthWritten)));
    }
  }

  Future<void> delete(PantryItem item) async {
    final eventId = await _repo.deleteItem(_hid, item, _user);
    _snack(_l.snackDeleted(item.name), () => _repo.undoFinish(_hid, item, eventId));
  }

  Future<void> addToShopping(PantryItem item) async {
    await _repo.addShopping(
      _hid,
      ShoppingEntry(id: '', name: item.name, categoryId: item.categoryId, productKey: productKeyOf(item)),
      _user,
    );
    _messenger?.showSnackBar(SnackBar(content: Text(_l.addedToShopping(item.name))));
  }

  Future<void> change(PantryItem original, PantryItem updated, HistoryType type) async {
    await _repo.updateItem(_hid, updated, history: type, by: _user);
    _snack(_l.snackChanged(original.name), () => _repo.updateItem(_hid, original));
  }

  static String _fmt(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

Future<void> finishWithFanfare(
  BuildContext context,
  WidgetRef ref,
  PantryItem item,
  ItemStatus how, {
  double? quantity,
}) async => ItemActions.of(context, ref)?.finish(item, how, quantity: quantity);

Future<void> showItemSheet(BuildContext context, WidgetRef ref, PantryItem item) {
  final actions = ItemActions.of(context, ref);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ItemSheet(item: item, actions: actions, host: context),
  );
}

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.item, required this.actions, required this.host});

  final PantryItem item;

  /// Screen below the sheet, for dialogs opened after the sheet closes.
  final BuildContext host;

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
                IconButton(
                  tooltip: l.deleteItem,
                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  onPressed: () {
                    Navigator.pop(context);
                    actions?.delete(item);
                  },
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
                  label: Text(
                    '${dateTypeLabel(l, item.dateType)}: ${formatDate(context, item.expiryDate)} '
                    '(${relativeExpiry(l, item.expiryDate, now)})',
                  ),
                  side: BorderSide(color: color),
                ),
                Chip(label: Text('${locationLabel(l, location)} · ${_qty(item)}')),
                if (item.isOpened) Chip(avatar: const Text('🔓'), label: Text(l.opened)),
                if (item.runningLow) Chip(avatar: const Text('📉'), label: Text(l.runningLow)),
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
                    onPressed: () => update(
                      item.copyWith(openedAt: now, expiryDate: expiryAfterOpening(item, now)),
                      HistoryType.opened,
                    ),
                    icon: const Text('🔓'),
                    label: Text(l.markOpened),
                  ),
                if (!item.isFrozen && location != LocationType.freezer)
                  TextButton.icon(
                    onPressed: () => update(
                      item.copyWith(
                        frozenAt: now,
                        expiryDate: expiryAfterFreezing(item, now),
                        locationType: LocationType.freezer,
                        locationId: LocationType.freezer.name,
                      ),
                      HistoryType.frozen,
                    ),
                    icon: const Text('❄️'),
                    label: Text(l.freeze),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (!host.mounted) return;
                    final edited = await showEditItemSheet(host, item);
                    if (edited != null) await actions?.change(item, edited, HistoryType.edited);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l.editItem),
                ),
                TextButton.icon(
                  onPressed: () => update(item.copyWith(runningLow: !item.runningLow), HistoryType.edited),
                  icon: const Text('📉'),
                  label: Text(item.runningLow ? l.unmarkRunningLow : l.markRunningLow),
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
                  onPressed: () {
                    Navigator.pop(context);
                    actions?.addToShopping(item);
                  },
                  icon: const Text('🛒'),
                  label: Text(l.toShopping),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    final key = productKeyOf(item);
                    final existing = (ref.read(stockRulesProvider).value ?? const []).where((r) => r.productKey == key);
                    editStockRule(
                      host,
                      ref,
                      existing.firstOrNull ??
                          StockRule(
                            productKey: key,
                            name: item.name,
                            minQuantity: 1,
                            unit: item.unit,
                            categoryId: item.categoryId,
                          ),
                    );
                  },
                  icon: const Text('🔁'),
                  label: Text(l.watchStock),
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
              child: Row(
                children: [
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
                ],
              ),
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

class _HealthSheet extends StatefulWidget {
  const _HealthSheet({required this.item, required this.grams});

  final PantryItem item;
  final double grams;

  @override
  State<_HealthSheet> createState() => _HealthSheetState();
}

class _HealthSheetState extends State<_HealthSheet> {
  late final _ctl = TextEditingController(text: widget.grams.round().toString());

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final g = double.tryParse(_ctl.text.replaceAll(',', '.')) ?? 0;
    final v = widget.item.nutrition!.forGrams(g);
    String r(double? x) => x == null ? '–' : x.round().toString();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('💚 ${l.healthHowMuch}', style: Theme.of(context).textTheme.titleLarge),
          Text(widget.item.name, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() => _ctl.text = '${(g - 25).clamp(0, 100000).round()}'),
              ),
              Expanded(
                child: TextField(
                  controller: _ctl,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l.healthGrams, suffixText: 'g'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _ctl.text = '${(g + 25).round()}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.healthPreview(r(v.kcal), r(v.protein), r(v.carbs), r(v.fat)), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l.healthSkip)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: g > 0 ? () => Navigator.pop(context, g) : null,
                  child: Text(l.healthWriteBtn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
