import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Fun little celebration: a big emoji pops in the middle of the screen with
/// smaller ones flying outwards. Used when food is eaten or thrown away.
void showBurst(BuildContext context, String emoji, {List<String> particles = const ['✨'], bool enabled = true}) {
  if (!enabled) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Burst(emoji: emoji, particles: particles, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Burst extends StatefulWidget {
  const _Burst({required this.emoji, required this.particles, required this.onDone});

  final String emoji;
  final List<String> particles;
  final VoidCallback onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward().whenComplete(widget.onDone);
  final _rnd = Random();
  late final _angles = List.generate(10, (i) => i * pi / 5 + _rnd.nextDouble() * 0.4);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final pop = Curves.elasticOut.transform((t * 1.6).clamp(0, 1));
          final fade = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
          return Opacity(
            opacity: fade,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final (i, a) in _angles.indexed)
                  Transform.translate(
                    offset: Offset(cos(a), sin(a)) * (40 + 140 * Curves.easeOut.transform(t)),
                    child: Text(widget.particles[i % widget.particles.length],
                        style: TextStyle(fontSize: 22 * (1 - t * 0.5))),
                  ),
                Transform.scale(scale: 0.2 + pop * 1.0, child: Text(widget.emoji, style: const TextStyle(fontSize: 96))),
              ],
            ),
          );
        },
      ),
    );
  }
}
