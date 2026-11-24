import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../theme.dart';

/// The home screen illustration: a fridge with the freezer below it and a
/// pantry cabinet. Tapping one opens its door while the "camera" moves in,
/// then the inside opens full screen (CompartmentScreen).
class FridgeView extends ConsumerStatefulWidget {
  const FridgeView({super.key, required this.items, required this.onItemTap});

  final List<PantryItem> items;
  final void Function(PantryItem) onItemTap;

  static LocationType placeOf(PantryItem i) {
    final t = i.locationType ?? suggestLocation(i.categoryId);
    return t == LocationType.other ? LocationType.pantry : t;
  }

  @override
  ConsumerState<FridgeView> createState() => _FridgeViewState();
}

class _FridgeViewState extends ConsumerState<FridgeView> with SingleTickerProviderStateMixin {
  late final _zoom = AnimationController(vsync: this);
  final _content = GlobalKey();
  Alignment _origin = Alignment.center;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Camera in → the inside full screen → camera back out.
  Future<void> _open(LocationType type, GlobalKey compartment) async {
    final s = ref.read(settingsProvider);
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    final target = compartment.currentContext?.findRenderObject() as RenderBox?;
    if (s.animations && box != null && target != null) {
      final c = box.globalToLocal(target.localToGlobal(target.size.center(Offset.zero)));
      setState(() => _origin = Alignment(c.dx / box.size.width * 2 - 1, c.dy / box.size.height * 2 - 1));
      await _zoom.animateTo(1, duration: const Duration(milliseconds: 480), curve: Curves.easeInCubic);
    }
    if (!mounted) return;
    await context.push('/place/${type.name}');
    if (mounted) _zoom.animateTo(0, duration: s.anim(const Duration(milliseconds: 380)), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    List<PantryItem> at(LocationType t) => sortByUrgency(widget.items.where((i) => FridgeView.placeOf(i) == t), now);
    final b = Theme.of(context).brightness;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(
            animation: _zoom,
            builder: (context, child) => Transform.scale(
              scale: 1 + 2.2 * _zoom.value,
              alignment: _origin,
              child: Opacity(opacity: (1 - _zoom.value * 0.6).clamp(0, 1), child: child),
            ),
            child: Column(
              key: _content,
              children: [
                // Fridge body
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GlebaColors.body(b),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: GlebaColors.bodyEdge(b), width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Compartment(
                        key: const ValueKey('fridge'),
                        type: LocationType.fridge,
                        items: at(LocationType.fridge),
                        height: 300,
                        onOpen: _open,
                      ),
                      const SizedBox(height: 8),
                      Compartment(
                        key: const ValueKey('freezer'),
                        type: LocationType.freezer,
                        items: at(LocationType.freezer),
                        height: 190,
                        onOpen: _open,
                      ),
                    ],
                  ),
                ),
                // Feet
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    2,
                    (_) => Container(
                      width: 36,
                      height: 8,
                      decoration: BoxDecoration(
                        color: GlebaColors.bodyEdge(b),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Compartment(
                  key: const ValueKey('pantry'),
                  type: LocationType.pantry,
                  items: at(LocationType.pantry),
                  height: 190,
                  onOpen: _open,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Compartment extends ConsumerStatefulWidget {
  const Compartment({
    super.key,
    required this.type,
    required this.items,
    required this.height,
    required this.onOpen,
  });

  final LocationType type;
  final List<PantryItem> items;
  final double height;

  /// Opens the inside; completes when the user comes back.
  final Future<void> Function(LocationType type, GlobalKey compartment) onOpen;

  @override
  ConsumerState<Compartment> createState() => _CompartmentState();
}

class _CompartmentState extends ConsumerState<Compartment> with TickerProviderStateMixin {
  late final AnimationController _door = AnimationController(vsync: this);
  final _key = GlobalKey();
  AnimationController? _shimmer;

  bool get _isFreezer => widget.type == LocationType.freezer;
  bool get _isPantry => widget.type == LocationType.pantry;

  @override
  void initState() {
    super.initState();
    _door.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ref.read(settingsProvider).animations;
    if (_isFreezer && anim && _shimmer == null) {
      _shimmer = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _door.dispose();
    _shimmer?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_door.value > 0.05) return;
    final s = ref.read(settingsProvider);
    // The door swings open while the camera moves in.
    _door.animateTo(1, duration: s.anim(const Duration(milliseconds: 520)), curve: Curves.easeOutCubic);
    await widget.onOpen(widget.type, _key);
    if (mounted) _door.animateTo(0, duration: s.anim(const Duration(milliseconds: 420)), curve: Curves.easeInOutCubic);
  }

  Matrix4 _swing(double angle) => Matrix4.identity()
    ..setEntry(3, 2, 0.0012)
    ..multiply(Matrix4.rotationY(angle));

  @override
  Widget build(BuildContext context) {
    final t = _door.value.clamp(0.0, 1.0);
    final b = Theme.of(context).brightness;
    final (top, bottom) = insideColors(widget.type, b);
    final door = _Door(type: widget.type, items: widget.items, shimmer: _shimmer, onTap: _open, wings: _isPantry);

    return SizedBox(
      key: _key,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // What you see behind the opening door.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
            ),
          ),
          if (t > 0 && t < 1 && ref.watch(settingsProvider).animations)
            IgnorePointer(child: CustomPaint(painter: _ColdBreathPainter(t, freezer: _isFreezer || _isPantry))),
          if (_isPantry) ...[
            // Two wing doors.
            Row(children: [
              Expanded(
                child: Transform(
                  alignment: Alignment.centerLeft,
                  transform: _swing(-t * pi * 0.55),
                  child: _Wing(left: true, onTap: _open),
                ),
              ),
              Expanded(
                child: Transform(
                  alignment: Alignment.centerRight,
                  transform: _swing(t * pi * 0.55),
                  child: _Wing(left: false, onTap: _open),
                ),
              ),
            ]),
            IgnorePointer(child: Opacity(opacity: (1 - t * 3).clamp(0, 1), child: door)),
          ] else
            Transform(
              // Fridge and freezer doors open to the same side.
              alignment: Alignment.centerLeft,
              transform: _swing(-t * pi * 0.55),
              child: door,
            ),
        ],
      ),
    );
  }
}

/// Inside colours (also the background of the full-screen inside).
(Color, Color) insideColors(LocationType t, Brightness b) => switch (t) {
      LocationType.freezer =>
        b == Brightness.light ? (const Color(0xFFDDE9F2), const Color(0xFFCFDFEB)) : (const Color(0xFF18273A), const Color(0xFF132131)),
      LocationType.pantry =>
        b == Brightness.light ? (const Color(0xFFEFE4D6), const Color(0xFFE6D7C4)) : (const Color(0xFF3A2E24), const Color(0xFF32271E)),
      _ => b == Brightness.light ? (const Color(0xFFEEF4F7), const Color(0xFFE4EDF2)) : (const Color(0xFF1D262D), const Color(0xFF182027)),
    };

Color _woodColor(Brightness b) => b == Brightness.light ? const Color(0xFFD9B48F) : const Color(0xFF6B4F37);
const _woodHandle = Color(0xFF8A6542);

/// One wing of the pantry's double door.
class _Wing extends StatelessWidget {
  const _Wing({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final r = const Radius.circular(20);
    return Material(
      color: _woodColor(b),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: left ? r : Radius.zero, right: left ? Radius.zero : r),
        side: BorderSide(color: _woodHandle.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _WoodPainter(b))),
          Positioned(
            top: 70,
            bottom: 70,
            left: left ? null : 8,
            right: left ? 8 : null,
            child: const _Handle(color: _woodHandle, horizontal: false),
          ),
        ]),
      ),
    );
  }
}

class _Door extends StatelessWidget {
  const _Door({required this.type, required this.items, required this.onTap, this.shimmer, this.wings = false});

  final LocationType type;
  final List<PantryItem> items;
  final VoidCallback onTap;
  final Animation<double>? shimmer;

  /// Only the writing – the pantry's wings are drawn separately.
  final bool wings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final l = context.l;
    final now = DateTime.now();
    final urgent = items.where((i) => freshnessOf(i, now) != Freshness.fresh).toList();
    final isPantry = type == LocationType.pantry;
    final isFreezer = type == LocationType.freezer;

    final doorColor = isFreezer
        ? (b == Brightness.light ? const Color(0xFFD6E6F1) : const Color(0xFF22374A))
        : GlebaColors.body(b);
    final handleColor = isFreezer
        ? (b == Brightness.light ? const Color(0xFFA9C2D3) : const Color(0xFF102030))
        : GlebaColors.bodyEdge(b);

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isFreezer ? '❄️' : (isPantry ? '🧺' : '🧊'), style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(locationLabel(l, type), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              _Badge(count: items.length, color: theme.colorScheme.primary),
              if (urgent.isNotEmpty) ...[
                const SizedBox(width: 6),
                _Badge(
                  count: urgent.length,
                  color: GlebaColors.freshness(freshnessOf(urgent.first, now), b),
                  icon: Icons.schedule,
                ),
              ],
            ],
          ),
          const Spacer(),
          // A peek at the most urgent food, like magnets on the door.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in urgent.take(isPantry ? 2 : 4))
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Text(categoryById(i.categoryId).emoji),
                  label: Text('${i.name} · ${relativeExpiry(l, i.expiryDate, now)}', overflow: TextOverflow.ellipsis),
                  side: BorderSide(color: GlebaColors.freshness(freshnessOf(i, now), b), width: 1.5),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l.tapToOpen, style: theme.textTheme.labelSmall?.copyWith(color: isPantry ? null : theme.colorScheme.outline)),
        ],
      ),
    );
    if (wings) return content;

    return Material(
      color: doorColor,
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (isFreezer && shimmer != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: shimmer!,
                  builder: (_, _) => CustomPaint(painter: _FrostPainter(shimmer!.value, b)),
                ),
              ),
            Positioned.fill(child: content),
            Positioned(right: 8, top: 40, bottom: 40, child: _Handle(color: handleColor, horizontal: false)),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color, required this.horizontal});

  final Color color;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => Container(
        width: horizontal ? null : 7,
        height: horizontal ? 7 : null,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3, offset: const Offset(1, 1))],
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.color, this.icon});

  final int count;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 3)],
            Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      );
}

/// One food item standing on a shelf. Drops in with a little bounce.
class ItemTile extends ConsumerWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onTap,
    this.index = 0,
    this.onLongPress,
    this.selected = false,
  });

  final PantryItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final f = freshnessOf(item, now);
    final color = GlebaColors.freshness(f, theme.brightness);
    final settings = ref.watch(settingsProvider);

    final tile = Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GlebaColors.ice, width: 2.5),
                )
              : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(bottom: BorderSide(color: color, width: 4)),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(categoryById(item.categoryId).emoji, style: const TextStyle(fontSize: 30)),
                  if (item.quantity > 1 && item.unit == 'ks')
                    Positioned(
                      right: -14,
                      top: -4,
                      child: _Badge(count: item.quantity.round(), color: theme.colorScheme.secondary),
                    ),
                  if (item.isOpened) const Positioned(left: -12, bottom: -2, child: Text('🔓', style: TextStyle(fontSize: 12))),
                ],
              ),
              const SizedBox(height: 4),
              // Always two lines tall, so tiles on a shelf line up.
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(theme.textTheme.labelMedium?.fontSize ?? 12) * 2.2 + 2,
                child: Center(
                  child: Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(height: 1.1)),
                ),
              ),
              const SizedBox(height: 2),
              Text(relativeExpiry(context.l, item.expiryDate, now),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );

    final decorated = Stack(clipBehavior: Clip.none, children: [
      SizedBox(width: double.infinity, child: tile),
      if (item.runningLow)
        Positioned(
          left: 4,
          top: 3,
          child: Text('📉', style: TextStyle(fontSize: 11, color: GlebaColors.freshness(Freshness.soon, theme.brightness))),
        ),
      if (selected)
        const Positioned(
          right: 4,
          top: 4,
          child: CircleAvatar(radius: 9, backgroundColor: GlebaColors.ice, child: Icon(Icons.check, size: 13, color: Colors.white)),
        ),
    ]);
    if (!settings.animations) return decorated;
    return TweenAnimationBuilder<double>(
      key: ValueKey(item.id),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + min(index, 12) * 70),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(0, (1 - v) * -30),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: Opacity(opacity: v.clamp(0, 1), child: child)),
      ),
      child: decorated,
    );
  }
}

/// Puffs of cold air escaping while the door opens.
class _ColdBreathPainter extends CustomPainter {
  _ColdBreathPainter(this.t, {required this.freezer});

  final double t;
  final bool freezer;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final fade = (1 - t).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    for (var i = 0; i < 12; i++) {
      final base = freezer
          ? Offset(rnd.nextDouble() * size.width, size.height * (0.2 + rnd.nextDouble() * 0.3))
          : Offset(size.width * (0.75 + rnd.nextDouble() * 0.2), rnd.nextDouble() * size.height);
      final drift = freezer ? Offset(0, -60 * t) : Offset(70 * t, -20 * t);
      canvas.drawCircle(base + drift, 14 + 30 * t * rnd.nextDouble(), paint);
    }
  }

  @override
  bool shouldRepaint(_ColdBreathPainter old) => old.t != t;
}

/// Frost crystals on the freezer door, slowly shimmering.
class _FrostPainter extends CustomPainter {
  _FrostPainter(this.t, this.brightness);

  final double t;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(42);
    final edge = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [GlebaColors.frost.withValues(alpha: brightness == Brightness.light ? 0.9 : 0.10), Colors.transparent],
      ).createShader(Offset.zero & Size(size.width, size.height * 0.45))
      ..blendMode = BlendMode.srcOver;
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45), edge);

    final dot = Paint();
    for (var i = 0; i < 60; i++) {
      final p = Offset(rnd.nextDouble() * size.width, size.height * (0.45 + rnd.nextDouble() * 0.55));
      final phase = rnd.nextDouble();
      final a = 0.2 + 0.6 * (0.5 + 0.5 * sin((t + phase) * 2 * pi));
      dot.color = Colors.white.withValues(alpha: a * (brightness == Brightness.light ? 0.9 : 0.3));
      _sparkle(canvas, p, 1.5 + rnd.nextDouble() * 2.5, dot);
    }
  }

  void _sparkle(Canvas c, Offset p, double r, Paint paint) {
    c.drawCircle(p, r * 0.6, paint);
    final line = Paint()
      ..color = paint.color
      ..strokeWidth = 0.8;
    c.drawLine(p - Offset(r * 1.8, 0), p + Offset(r * 1.8, 0), line);
    c.drawLine(p - Offset(0, r * 1.8), p + Offset(0, r * 1.8), line);
  }

  @override
  bool shouldRepaint(_FrostPainter old) => old.t != t || old.brightness != brightness;
}

class _WoodPainter extends CustomPainter {
  _WoodPainter(this.brightness);

  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(3);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.brown.withValues(alpha: brightness == Brightness.light ? 0.12 : 0.25);
    for (var i = 0; i < 14; i++) {
      final y = rnd.nextDouble() * size.height;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 40) {
        path.lineTo(x, y + sin(x / 60 + i) * 4);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_WoodPainter old) => old.brightness != brightness;
}
