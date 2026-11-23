import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../fridge/fridge_view.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/burst.dart';
import '../widgets/item_sheet.dart' show restock;

enum _Act { keep, eaten, thrown, part }

class _Done {
  _Done(this.item, this.act, {this.eventId});

  final PantryItem item;
  final _Act act;
  final String? eventId;
}

/// Quick fridge check: swipe through the items one by one.
/// Right = still there, left = eaten, up = only part left; a button for thrown away.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.filter});

  /// 'expired' = only items long past their date; a LocationType name; or null.
  final String? filter;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late String? _filter = widget.filter;
  List<PantryItem>? _queue;
  int _index = 0;
  final _done = <_Done>[];
  Offset _drag = Offset.zero;
  late final AnimationController _fly = AnimationController(vsync: this);
  Animation<Offset>? _flyAnim;

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  /// Snapshot of the items to check, most urgent first.
  List<PantryItem> _build(List<PantryItem> items) {
    final now = DateTime.now();
    final list = items.where(
      (i) => switch (_filter) {
        null => true,
        'expired' => daysLeft(i.expiryDate, now) < -3,
        final loc => FridgeView.placeOf(i).name == loc,
      },
    );
    return sortByUrgency(list, now);
  }

  void _setFilter(String? f) => setState(() {
    _filter = f;
    _queue = null;
    _index = 0;
    _done.clear();
  });

  Duration _d(int ms) => ref.read(settingsProvider).anim(Duration(milliseconds: ms));

  Future<void> _act(_Act act) async {
    final queue = _queue!;
    if (_index >= queue.length) return;
    final item = queue[_index];
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final repo = ref.read(repositoryProvider);

    double? partQty;
    if (act == _Act.part) {
      partQty = await _askRemaining(item);
      if (partQty == null) {
        setState(() => _drag = Offset.zero);
        return;
      }
    }

    // Fly the card out in the swipe direction.
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final target = switch (act) {
      _Act.keep => Offset(size.width * 1.3, _drag.dy),
      _Act.eaten => Offset(-size.width * 1.3, _drag.dy),
      _Act.part => Offset(_drag.dx, -size.height),
      _Act.thrown => Offset(0, size.height),
    };
    _flyAnim = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _fly, curve: Curves.easeIn));
    _fly.duration = _d(260);
    await _fly.forward(from: 0);

    String? eventId;
    switch (act) {
      case _Act.keep:
        await repo.updateItem(h.id, item.copyWith(checkedAt: DateTime.now()));
      case _Act.eaten:
        eventId = await repo.finishItem(h.id, item, ItemStatus.consumed, user);
      case _Act.thrown:
        eventId = await repo.finishItem(h.id, item, ItemStatus.discarded, user);
      case _Act.part:
        final used = item.quantity - partQty!;
        if (used > 0) eventId = await repo.finishItem(h.id, item, ItemStatus.consumed, user, quantity: used);
    }
    if (act != _Act.keep) await restock(repo, h.id, user);
    if (!mounted) return;
    setState(() {
      _done.add(_Done(item, act, eventId: eventId));
      _index++;
      _drag = Offset.zero;
      _flyAnim = null;
      _fly.reset();
    });
    if (_index == queue.length) {
      showBurst(context, '🎉', particles: const ['✨', '🧊', '⭐'], enabled: ref.read(settingsProvider).animations);
    }
  }

  Future<void> _undo() async {
    if (_done.isEmpty) return;
    final last = _done.removeLast();
    final h = ref.read(activeHouseholdProvider);
    if (h == null) return;
    final repo = ref.read(repositoryProvider);
    if (last.eventId != null) {
      await repo.undoFinish(h.id, last.item, last.eventId!);
    } else {
      await repo.updateItem(h.id, last.item);
    }
    setState(() => _index--);
  }

  Future<double?> _askRemaining(PantryItem item) {
    final l = context.l;
    final countable = item.unit == 'ks' && item.quantity > 1;
    return showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${l.invHowMuchLeft} · ${item.name}'),
        children: [
          if (countable)
            for (var q = item.quantity.toInt() - 1; q >= 1; q--)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, q.toDouble()), child: Text('$q ${item.unit}'))
          else
            for (final (label, f) in [('¾', .75), ('½', .5), ('¼', .25)])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, double.parse((item.quantity * f).toStringAsFixed(2))),
                child: Text('$label  (${_q(item.quantity * f)} ${item.unit})'),
              ),
        ],
      ),
    );
  }

  static String _q(double q) => q == q.roundToDouble() ? '${q.toInt()}' : q.toStringAsFixed(1);

  _Act? _dragAct(Size size) {
    if (_drag.dy < -size.height * 0.15 && _drag.dy.abs() > _drag.dx.abs()) return _Act.part;
    if (_drag.dx > size.width * 0.25) return _Act.keep;
    if (_drag.dx < -size.width * 0.25) return _Act.eaten;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final items = ref.watch(itemsProvider).value;
    if (items != null && _queue == null) _queue = _build(items);
    final queue = _queue ?? const <PantryItem>[];
    final finished = _queue != null && _index >= queue.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.inventoryTitle),
        actions: [if (_done.isNotEmpty) IconButton(tooltip: l.undo, icon: const Icon(Icons.undo), onPressed: _undo)],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final (value, label) in [
                  (null, l.invAll),
                  ('fridge', l.fridge),
                  ('freezer', l.freezer),
                  ('pantry', l.pantry),
                  ('expired', l.invExpired),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => _setFilter(value),
                    ),
                  ),
              ],
            ),
          ),
          if (!finished && queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _index / queue.length, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 4),
                  Text(l.invProgress(_index + 1, queue.length), style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          Expanded(
            child: _queue == null
                ? const Center(child: CircularProgressIndicator())
                : queue.isEmpty
                ? Center(child: Text(l.invNothing))
                : finished
                ? _summary(context)
                : _cards(context, queue),
          ),
          if (!finished && queue.isNotEmpty) ...[
            Text(l.invHint, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    _ActionButton(emoji: '🗑️', label: l.invThrown, onTap: () => _act(_Act.thrown)),
                    _ActionButton(emoji: '😋', label: l.invEaten, onTap: () => _act(_Act.eaten)),
                    _ActionButton(emoji: '½', label: l.invPart, onTap: () => _act(_Act.part)),
                    _ActionButton(emoji: '✅', label: l.invStillThere, onTap: () => _act(_Act.keep), primary: true),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cards(BuildContext context, List<PantryItem> queue) {
    final size = MediaQuery.sizeOf(context);
    final l = context.l;
    return LayoutBuilder(
      builder: (context, box) {
        final next = _index + 1 < queue.length ? queue[_index + 1] : null;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (next != null)
              Transform.scale(
                scale: 0.94,
                child: Opacity(
                  opacity: 0.6,
                  child: _ItemCard(item: next, maxHeight: box.maxHeight - 16),
                ),
              ),
            AnimatedBuilder(
              animation: _fly,
              builder: (context, child) {
                final offset = _flyAnim?.value ?? _drag;
                final act = _flyAnim == null ? _dragAct(size) : null;
                return Transform.translate(
                  offset: offset,
                  child: Transform.rotate(
                    angle: offset.dx / 900,
                    child: Stack(
                      children: [
                        child!,
                        if (act != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _Stamp(
                                text: switch (act) {
                                  _Act.keep => '✅ ${l.invStillThere}',
                                  _Act.eaten => '😋 ${l.invEaten}',
                                  _Act.part => '½ ${l.invPart}',
                                  _Act.thrown => '🗑️',
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _drag += d.delta),
                onPanEnd: (_) {
                  final act = _dragAct(size);
                  if (act == null) {
                    setState(() => _drag = Offset.zero);
                  } else {
                    _act(act);
                  }
                },
                child: _ItemCard(item: queue[_index], maxHeight: box.maxHeight - 16),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summary(BuildContext context) {
    final l = context.l;
    int n(_Act a) => _done.where((d) => d.act == a).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧊', style: TextStyle(fontSize: 72)),
            Text(l.invDone, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(l.invSummary(_done.length, n(_Act.eaten), n(_Act.thrown), n(_Act.part)), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.invBack)),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.maxHeight = double.infinity});

  final PantryItem item;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final color = GlebaColors.freshness(freshnessOf(item, now), theme.brightness);
    final w = min(MediaQuery.sizeOf(context).width - 48, 360.0);
    return SizedBox(
      width: w,
      height: min(w * 1.15, maxHeight),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: color, width: 3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          // Scales down on short screens / large fonts instead of overflowing.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: w - 46,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(categoryById(item.categoryId).emoji, style: const TextStyle(fontSize: 88)),
                  const SizedBox(height: 12),
                  Text(item.name, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.headlineSmall),
                  if (item.brand != null) Text(item.brand!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(locationLabel(l, FridgeView.placeOf(item)))),
                      Chip(
                        label: Text(
                          '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toInt() : item.quantity} ${item.unit}',
                        ),
                      ),
                      if (item.isOpened) Chip(avatar: const Text('🔓'), label: Text(l.opened)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${dateTypeLabel(l, item.dateType)}: ${relativeExpiry(l, item.expiryDate, now)}',
                    style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.rotate(
      angle: -0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
        ),
        child: Text(text, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.emoji, required this.label, required this.onTap, this.primary = false});

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? FilledButton.styleFrom()
        : FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilledButton(
          style: style.copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8, horizontal: 2)),
            minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
          ),
          onPressed: onTap,
          child: FittedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                Text(label, maxLines: 1, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
