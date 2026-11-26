import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/merge.dart';
import '../../domain/models.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/item_sheet.dart';
import 'fridge_view.dart';

/// Inside the fridge / freezer / pantry, full screen ("the camera went in").
/// The decoration – light, glass shelves, drawers, icicles, wood – stays in
/// the background in muted colours; the food tiles are what you look at.
/// Long-press starts selecting several items for one action.
class CompartmentScreen extends ConsumerStatefulWidget {
  const CompartmentScreen({super.key, required this.type});

  final LocationType type;

  @override
  ConsumerState<CompartmentScreen> createState() => _CompartmentScreenState();
}

/// Vegetables and fruit go into the drawers at the bottom of the fridge.
const _drawerCategories = {'vegetables', 'fruit', 'rootVeg'};

class _CompartmentScreenState extends ConsumerState<CompartmentScreen> {
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(PantryItem i) => setState(() => _selected.contains(i.id) ? _selected.remove(i.id) : _selected.add(i.id));

  Future<void> _bulk(List<PantryItem> all, Future<void> Function(ItemActions a, List<PantryItem> items) run) async {
    final items = all.where((i) => _selected.contains(i.id)).toList();
    final actions = ItemActions.of(context, ref);
    setState(_selected.clear);
    if (actions != null && items.isNotEmpty) await run(actions, items);
  }

  Future<void> _cook(List<PantryItem> all) async {
    final l = context.l;
    final name = TextEditingController(text: l.cookedDefaultName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.cookTitle),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.cookText, style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.cookName)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.cookDo)),
        ],
      ),
    );
    final text = name.text.trim();
    if (ok != true || !mounted) return;
    await _bulk(all, (a, items) => a.cook(items, text.isEmpty ? l.cookedDefaultName : text));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = DateTime.now();
    final all = ref.watch(itemsProvider).value ?? const <PantryItem>[];
    final items = groupSameNames(sortByUrgency(all.where((i) => FridgeView.placeOf(i) == widget.type), now));
    _selected.removeWhere((id) => !items.any((i) => i.id == id));
    final isFridge = widget.type == LocationType.fridge;
    final shelfItems = isFridge ? items.where((i) => !_drawerCategories.contains(i.categoryId)).toList() : items;
    final drawerItems = isFridge ? items.where((i) => _drawerCategories.contains(i.categoryId)).toList() : const <PantryItem>[];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          title: Text(_selecting ? l.selectedCount(_selected.length) : '${locationLabel(l, widget.type)} · ${items.length}'),
          leading: _selecting
              ? IconButton(tooltip: l.cancel, icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear))
              : null,
          backgroundColor: _InteriorBackground.topColor(widget.type, Theme.of(context).brightness),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _InteriorBackground(type: widget.type)),
            if (items.isEmpty)
              Center(child: Text(l.emptyShelf))
            else
              LayoutBuilder(builder: (context, box) {
                final perRow = max(4, min(8, (box.maxWidth / 100).floor()));
                return ListView(
                  padding: EdgeInsets.fromLTRB(10, widget.type == LocationType.freezer ? 24 : 14, 10, _selecting ? 110 : 32),
                  children: [
                    for (var r = 0; r < shelfItems.length; r += perRow)
                      _Shelf(
                        type: widget.type,
                        perRow: perRow,
                        children: [
                          for (final i in shelfItems.skip(r).take(perRow)) _tile(i, r),
                        ],
                      ),
                    if (drawerItems.isNotEmpty) _Drawer(perRow: perRow, children: [for (final i in drawerItems) _tile(i, 0)]),
                  ],
                );
              }),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: SafeArea(
                child: AnimatedSlide(
                  offset: _selecting ? Offset.zero : const Offset(0, 1.6),
                  duration: ref.watch(settingsProvider).anim(const Duration(milliseconds: 220)),
                  curve: Curves.easeOutCubic,
                  child: _SelectionBar(
                    onEat: () => _bulk(items, (a, x) => a.finishMany(x, ItemStatus.consumed)),
                    onCook: () => _cook(items),
                    onThrow: () => _bulk(items, (a, x) => a.finishMany(x, ItemStatus.discarded)),
                    onDelete: () => _bulk(items, (a, x) => a.deleteMany(x)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(PantryItem i, int index) => ItemTile(
        item: i,
        index: index,
        selected: _selected.contains(i.id),
        onTap: () => _selecting ? _toggle(i) : showItemSheet(context, ref, i),
        onLongPress: () => _toggle(i),
      );
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.type, required this.perRow, required this.children});

  final LocationType type;
  final int perRow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final shelf = switch (type) {
      LocationType.freezer => BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          // Frost on the edge of the rack.
          gradient: LinearGradient(colors: [
            for (var k = 0; k < 24; k++) Colors.white.withValues(alpha: (k.isEven ? 0.85 : 0.45) * (b == Brightness.light ? 1 : 0.25)),
          ]),
        ),
      LocationType.pantry => BoxDecoration(
          color: b == Brightness.light ? const Color(0xFFB39373) : const Color(0xFF6E5440),
          borderRadius: BorderRadius.circular(3),
        ),
      _ => BoxDecoration(
          color: Colors.white.withValues(alpha: b == Brightness.light ? 0.75 : 0.10),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: GlebaColors.ice.withValues(alpha: b == Brightness.light ? 0.28 : 0.18)),
        ),
    };
    return Column(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 0; k < perRow; k++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: k < children.length ? children[k] : const SizedBox(),
              ),
            ),
        ],
      ),
      Container(height: 6, margin: const EdgeInsets.only(top: 3, bottom: 12), decoration: shelf),
    ]);
  }
}

/// The vegetable drawer at the bottom of the fridge.
class _Drawer extends StatelessWidget {
  const _Drawer({required this.perRow, required this.children});

  final int perRow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final edge = GlebaColors.ice.withValues(alpha: b == Brightness.light ? 0.28 : 0.18);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      decoration: BoxDecoration(
        color: (b == Brightness.light ? const Color(0xFFD2E0E8) : Colors.white).withValues(alpha: b == Brightness.light ? 0.5 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edge),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        // The drawer's handle.
        Positioned(
          top: -8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(width: 60, height: 4, decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(2))),
          ),
        ),
        Column(children: [
          for (var r = 0; r < children.length; r += perRow)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var k = 0; k < perRow; k++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: r + k < children.length ? children[r + k] : const SizedBox(),
                    ),
                  ),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.onEat, required this.onCook, required this.onThrow, required this.onDelete});

  final VoidCallback onEat;
  final VoidCallback onCook;
  final VoidCallback onThrow;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    Widget b(String emoji, String label, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                minimumSize: const Size(0, 56),
              ),
              onPressed: onTap,
              child: FittedBox(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  Text(label),
                ]),
              ),
            ),
          ),
        );
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          b('😋', l.bulkEat, onEat),
          b('🍲', l.bulkCook, onCook),
          b('🗑️', l.bulkThrow, onThrow),
          b('❌', l.bulkDelete, onDelete),
        ]),
      ),
    );
  }
}

/// Muted background art: light, icicles or wood grain. Never on top of food.
class _InteriorBackground extends StatelessWidget {
  const _InteriorBackground({required this.type});

  final LocationType type;

  static (Color, Color) colors(LocationType t, Brightness b) => insideColors(t, b);

  static Color topColor(LocationType t, Brightness b) => colors(t, b).$1;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final (top, bottom) = colors(type, b);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])),
      child: CustomPaint(painter: _DecorPainter(type, b)),
    );
  }
}

class _DecorPainter extends CustomPainter {
  _DecorPainter(this.type, this.b);

  final LocationType type;
  final Brightness b;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case LocationType.freezer:
        // Icicles hanging from the top.
        final p = Paint()..color = Colors.white.withValues(alpha: b == Brightness.light ? 0.8 : 0.22);
        for (var x = 4.0; x < size.width; x += 13) {
          final h = 6 + ((x * 37).round() % 14).toDouble();
          canvas.drawPath(Path()..moveTo(x, 0)..lineTo(x + 5, 0)..lineTo(x + 2.5, h)..close(), p);
        }
      case LocationType.pantry:
        // Wood grain.
        final p = Paint()
          ..color = (b == Brightness.light ? const Color(0xFF785532) : Colors.black).withValues(alpha: b == Brightness.light ? 0.07 : 0.18)
          ..strokeWidth = 2;
        for (var x = 0.0; x < size.width; x += 14) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
      default:
        // The fridge light.
        final light = b == Brightness.light ? const Color(0xFFFFFDF3) : const Color(0xFF2C3840);
        final c = Offset(size.width / 2, 0);
        canvas.drawCircle(
          c,
          size.width * 0.6,
          Paint()..shader = RadialGradient(colors: [light, light.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: size.width * 0.6)),
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromCenter(center: c + const Offset(0, 3), width: 64, height: 7),
              bottomLeft: const Radius.circular(8), bottomRight: const Radius.circular(8)),
          Paint()..color = light,
        );
    }
  }

  @override
  bool shouldRepaint(_DecorPainter old) => old.type != type || old.b != b;
}
