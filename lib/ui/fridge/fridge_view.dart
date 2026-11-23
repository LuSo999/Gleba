import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../theme.dart';

/// The home screen illustration: a fridge with the freezer below it and a
/// pantry cabinet. Each compartment opens with an animation and shows its food
/// on shelves, coloured by freshness.
class FridgeView extends ConsumerWidget {
  const FridgeView({super.key, required this.items, required this.onItemTap});

  final List<PantryItem> items;
  final void Function(PantryItem) onItemTap;

  static LocationType placeOf(PantryItem i) {
    final t = i.locationType ?? suggestLocation(i.categoryId);
    return t == LocationType.other ? LocationType.pantry : t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    List<PantryItem> at(LocationType t) => sortByUrgency(items.where((i) => placeOf(i) == t), now);
    final b = Theme.of(context).brightness;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
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
                      height: 380,
                      onItemTap: onItemTap,
                    ),
                    const SizedBox(height: 8),
                    Compartment(
                      key: const ValueKey('freezer'),
                      type: LocationType.freezer,
                      items: at(LocationType.freezer),
                      height: 240,
                      onItemTap: onItemTap,
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
                height: 220,
                onItemTap: onItemTap,
              ),
            ],
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
    required this.onItemTap,
  });

  final LocationType type;
  final List<PantryItem> items;
  final double height;
  final void Function(PantryItem) onItemTap;

  @override
  ConsumerState<Compartment> createState() => _CompartmentState();
}

class _CompartmentState extends ConsumerState<Compartment> with TickerProviderStateMixin {
  late final AnimationController _door = AnimationController(vsync: this);
  AnimationController? _shimmer;

  bool get _isFreezer => widget.type == LocationType.freezer;

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

  void _toggle() {
    final s = ref.read(settingsProvider);
    if (_door.value > 0.5) {
      _door.animateTo(0, duration: s.anim(const Duration(milliseconds: 420)), curve: Curves.easeInCubic);
    } else {
      _door.animateTo(1, duration: s.anim(const Duration(milliseconds: 750)), curve: Curves.easeOutBack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _door.value.clamp(0.0, 1.0);
    final doorGone = t > 0.97;
    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Interior(type: widget.type, items: widget.items, glow: t, onItemTap: widget.onItemTap, onClose: _toggle),
          if (t > 0 && t < 1 && ref.watch(settingsProvider).animations)
            IgnorePointer(child: CustomPaint(painter: _ColdBreathPainter(t, freezer: _isFreezer))),
          if (!doorGone)
            IgnorePointer(
              ignoring: t > 0.05,
              child: Transform(
                alignment: _isFreezer ? Alignment.bottomCenter : Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..multiply(_isFreezer ? Matrix4.rotationX(-t * pi / 2) : Matrix4.rotationY(-t * pi / 2)),
                child: _Door(
                  type: widget.type,
                  items: widget.items,
                  shimmer: _shimmer,
                  onTap: _toggle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Door extends StatelessWidget {
  const _Door({required this.type, required this.items, required this.onTap, this.shimmer});

  final LocationType type;
  final List<PantryItem> items;
  final VoidCallback onTap;
  final Animation<double>? shimmer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final l = context.l;
    final now = DateTime.now();
    final urgent = items.where((i) => freshnessOf(i, now) != Freshness.fresh).toList();
    final isPantry = type == LocationType.pantry;
    final isFreezer = type == LocationType.freezer;

    final doorColor = isPantry
        ? (b == Brightness.light ? const Color(0xFFD9B48F) : const Color(0xFF6B4F37))
        : GlebaColors.body(b);
    final handleColor = isPantry ? const Color(0xFF8A6542) : GlebaColors.bodyEdge(b);

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
              for (final i in urgent.take(4))
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Text(categoryById(i.categoryId).emoji),
                  label: Text('${i.name} · ${relativeExpiry(l, i.expiryDate, now)}', overflow: TextOverflow.ellipsis),
                  side: BorderSide(color: GlebaColors.freshness(freshnessOf(i, now), b), width: 1.5),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l.tapToOpen, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );

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
            if (isPantry) Positioned.fill(child: CustomPaint(painter: _WoodPainter(b))),
            Positioned.fill(child: content),
            // Handle
            if (isFreezer)
              Positioned(top: 8, left: 60, right: 60, child: _Handle(color: handleColor, horizontal: true))
            else
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

class _Interior extends ConsumerWidget {
  const _Interior({
    required this.type,
    required this.items,
    required this.glow,
    required this.onItemTap,
    required this.onClose,
  });

  final LocationType type;
  final List<PantryItem> items;
  final double glow;
  final void Function(PantryItem) onItemTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final isPantry = type == LocationType.pantry;
    final base = isPantry
        ? (b == Brightness.light ? const Color(0xFFF3E6D6) : const Color(0xFF3A2E24))
        : GlebaColors.interior(b);
    const perShelf = 3;
    final shelves = <List<PantryItem>>[
      for (var i = 0; i < items.length; i += perShelf) items.sublist(i, min(i + perShelf, items.length)),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.4,
            colors: [Color.lerp(base, GlebaColors.interiorLight(b), glow.clamp(0, 1))!, base],
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Text(locationLabel(context.l, type), style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    const Icon(Icons.close, size: 18),
                  ],
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: _FlickeringEmpty())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: shelves.length,
                      itemBuilder: (context, s) => _Shelf(
                        items: shelves[s],
                        perShelf: perShelf,
                        startIndex: s * perShelf,
                        glass: !isPantry,
                        onItemTap: onItemTap,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.items,
    required this.perShelf,
    required this.startIndex,
    required this.glass,
    required this.onItemTap,
  });

  final List<PantryItem> items;
  final int perShelf;
  final int startIndex;
  final bool glass;
  final void Function(PantryItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < perShelf; i++)
              Expanded(
                child: i < items.length
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ItemTile(item: items[i], index: startIndex + i, onTap: () => onItemTap(items[i])),
                      )
                    : const SizedBox(),
              ),
          ],
        ),
        Container(
          height: 6,
          margin: const EdgeInsets.only(top: 2, bottom: 10),
          decoration: BoxDecoration(
            color: glass
                ? (b == Brightness.light ? Colors.white.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.12))
                : const Color(0xFFA67C52),
            borderRadius: BorderRadius.circular(3),
            border: glass ? Border.all(color: GlebaColors.ice.withValues(alpha: 0.35)) : null,
          ),
        ),
      ],
    );
  }
}

/// One food item standing on a shelf. Drops in with a little bounce.
class ItemTile extends ConsumerWidget {
  const ItemTile({super.key, required this.item, required this.onTap, this.index = 0});

  final PantryItem item;
  final VoidCallback onTap;
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
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
              Text(item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(height: 1.1)),
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

    if (!settings.animations) return tile;
    return TweenAnimationBuilder<double>(
      key: ValueKey(item.id),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + min(index, 12) * 70),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(0, (1 - v) * -30),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: Opacity(opacity: v.clamp(0, 1), child: child)),
      ),
      child: tile,
    );
  }
}

/// Empty compartment: the light flickers and the crickets chirp.
class _FlickeringEmpty extends StatefulWidget {
  const _FlickeringEmpty();

  @override
  State<_FlickeringEmpty> createState() => _FlickeringEmptyState();
}

class _FlickeringEmptyState extends State<_FlickeringEmpty> {
  Timer? _timer;
  double _opacity = 1;
  int _ticks = 0;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      if (++_ticks > 14) {
        t.cancel();
        setState(() => _opacity = 1);
        return;
      }
      setState(() => _opacity = _rnd.nextBool() ? 1 : 0.25);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: _opacity,
        child: Text(context.l.emptyShelf, style: Theme.of(context).textTheme.bodyMedium),
      );
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
        colors: [GlebaColors.frost.withValues(alpha: brightness == Brightness.light ? 0.9 : 0.25), Colors.transparent],
      ).createShader(Offset.zero & Size(size.width, size.height * 0.45))
      ..blendMode = BlendMode.srcOver;
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45), edge);

    final dot = Paint();
    for (var i = 0; i < 60; i++) {
      final p = Offset(rnd.nextDouble() * size.width, size.height * (0.45 + rnd.nextDouble() * 0.55));
      final phase = rnd.nextDouble();
      final a = 0.2 + 0.6 * (0.5 + 0.5 * sin((t + phase) * 2 * pi));
      dot.color = Colors.white.withValues(alpha: a * (brightness == Brightness.light ? 0.9 : 0.5));
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
