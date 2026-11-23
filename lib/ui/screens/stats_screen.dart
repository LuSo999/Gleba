import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../domain/notification_rules.dart';
import '../../domain/shelf_life.dart';
import '../../domain/stats.dart';
import '../labels.dart';

/// Chart colours: validated categorical slots 1 (blue) and 2 (orange), each
/// stepped for its surface (see the dataviz palette). Text never uses them.
class _Viz {
  static Color eaten(Brightness b) => b == Brightness.light ? const Color(0xFF2A78D6) : const Color(0xFF3987E5);
  static Color thrown(Brightness b) => b == Brightness.light ? const Color(0xFFEB6834) : const Color(0xFFD95926);
  static Color grid(BuildContext c) => Theme.of(c).colorScheme.outlineVariant.withValues(alpha: 0.6);
}

final _periodProvider = NotifierProvider<_Period, int?>(_Period.new);

class _Period extends Notifier<int?> {
  @override
  int? build() => 30;

  void set(int? days) => state = days;
}

final _statsProvider = FutureProvider<Stats?>((ref) async {
  final h = ref.watch(activeHouseholdProvider);
  final days = ref.watch(_periodProvider);
  ref.watch(historyProvider); // refresh when something happens
  if (h == null) return null;
  final now = DateTime.now();
  // Load twice the period so we can compare with the previous one.
  final since = days == null ? null : now.subtract(Duration(days: days * 2));
  final events = await ref.read(repositoryProvider).fetchEvents(h.id, since: since);
  return computeStats(events, now, days: days);
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final period = ref.watch(_periodProvider);
    final stats = ref.watch(_statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.statsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Filters: one row above the charts.
          SegmentedButton<int?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 30, label: Text(l.stats30)),
              ButtonSegment(value: 90, label: Text(l.stats90)),
              ButtonSegment(value: 365, label: Text(l.stats365)),
              ButtonSegment(value: null, label: Text(l.statsAll)),
            ],
            selected: {period},
            onSelectionChanged: (s) => ref.read(_periodProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 16),
          ...switch (stats) {
            AsyncData(value: final s?) when s.removals > 0 || s.members.isNotEmpty => _content(context, ref, s),
            AsyncData() => [Padding(padding: const EdgeInsets.all(32), child: Text(l.statsEmpty, textAlign: TextAlign.center))],
            AsyncError(:final error) => [Text('$error', style: TextStyle(color: theme.colorScheme.error))],
            _ => [const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))],
          },
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, Stats s) {
    final l = context.l;
    final theme = Theme.of(context);
    String pct(double v) => '${(v * 100).round()} %';
    final shareDelta = s.previousShare == null ? null : ((s.discardedShare - s.previousShare!) * 100).round();
    final tips = statsTips(s);

    return [
      // KPI row of stat tiles (equal heights).
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _StatTile(label: l.statsEatenShare, value: pct(s.eatenShare), detail: l.statsPieces(s.eaten))),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            label: l.statsThrown,
            value: pct(s.discardedShare),
            detail: shareDelta == null || shareDelta == 0
                ? l.statsPieces(s.discarded)
                : l.statsVsPrev('${shareDelta > 0 ? '▲ +' : '▼ '}$shareDelta p. b.'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            label: l.statsThrownValue,
            value: '${s.discardedValue.round()} Kč',
            detail: l.statsPieces(s.discarded),
          ),
        ),
      ])),
      if (s.discarded > 0 && s.discardedValue == 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l.statsPriceHint, style: theme.textTheme.bodySmall),
        ),
      if (tips.isNotEmpty) ...[
        const SizedBox(height: 16),
        for (final t in tips) _TipCard(tip: t),
      ],
      const SizedBox(height: 24),
      _SectionTitle('${l.statsOverTime} · ${s.monthly ? l.statsPerMonth : l.statsPerWeek}'),
      _Legend(eaten: s.eaten, discarded: s.discarded),
      const SizedBox(height: 8),
      SizedBox(height: 200, child: _StackedColumns(stats: s)),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(l.statsTable, style: theme.textTheme.bodyMedium),
        children: [
          DataTable(
            columnSpacing: 24,
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columns: [
              DataColumn(label: Text(s.monthly ? l.statsPerMonth : l.statsPerWeek)),
              DataColumn(label: Text(l.statsEaten), numeric: true),
              DataColumn(label: Text(l.statsThrown), numeric: true),
            ],
            rows: [
              for (final b in s.buckets.reversed)
                DataRow(cells: [
                  DataCell(Text(_bucketLabel(context, b.start, s.monthly))),
                  DataCell(Text('${b.eaten}')),
                  DataCell(Text('${b.discarded}')),
                ]),
            ],
          ),
        ],
      ),
      if (s.categories.isNotEmpty) ...[
        const SizedBox(height: 16),
        _SectionTitle(l.statsTopCategories),
        _CategoryBars(categories: s.categories.take(6).toList()),
      ],
      if (s.products.isNotEmpty) ...[
        const SizedBox(height: 16),
        _SectionTitle(l.statsTopProducts),
        for (final p in s.products)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(p.key), trailing: Text('${p.value}×')),
      ],
      if (s.members.length > 1 || (s.members.isNotEmpty && s.members.first.name != '?')) ...[
        const SizedBox(height: 16),
        _SectionTitle(l.statsMembers),
        for (final m in s.members)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
            title: Text(m.name),
            subtitle: Text('➕ ${m.added} ${l.statsAdded} · 😋 ${m.eaten} · 🗑️ ${m.discarded}'),
          ),
      ],
    ];
  }
}

/// Week buckets are labelled by their Monday ("17. 11."), months by name.
String _bucketLabel(BuildContext context, DateTime d, bool monthly) =>
    monthly ? MaterialLocalizations.of(context).formatMonthYear(d) : '${d.day}. ${d.month}.';

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.labelMedium?.copyWith(color: muted), maxLines: 2),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(height: 2),
          Text(detail, style: t.labelSmall?.copyWith(color: muted), maxLines: 2),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.eaten, required this.discarded});

  final int eaten;
  final int discarded;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final l = context.l;
    Widget item(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Wrap(spacing: 16, children: [
      item(_Viz.eaten(b), '${l.statsEaten} $eaten'),
      item(_Viz.thrown(b), '${l.statsThrown} $discarded'),
    ]);
  }
}

/// Stacked columns per week/month: eaten at the base, thrown away on top,
/// 2px surface gap between segments, rounded data end, tap for a tooltip.
class _StackedColumns extends StatefulWidget {
  const _StackedColumns({required this.stats});

  final Stats stats;

  @override
  State<_StackedColumns> createState() => _StackedColumnsState();
}

class _StackedColumnsState extends State<_StackedColumns> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final theme = Theme.of(context);
    final b = theme.brightness;
    return LayoutBuilder(builder: (context, c) {
      const axisW = 28.0, labelH = 18.0;
      final plotW = c.maxWidth - axisW;
      final slot = plotW / s.buckets.length;
      final maxV = s.buckets.fold<int>(1, (m, x) => x.eaten + x.discarded > m ? x.eaten + x.discarded : m);
      final sel = _selected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final i = ((d.localPosition.dx - axisW) / slot).floor();
          setState(() => _selected = i >= 0 && i < s.buckets.length && i != _selected ? i : null);
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ColumnsPainter(
                stats: s,
                maxV: maxV,
                axisW: axisW,
                labelH: labelH,
                eaten: _Viz.eaten(b),
                thrown: _Viz.thrown(b),
                surface: theme.cardTheme.color ?? theme.colorScheme.surface,
                grid: _Viz.grid(context),
                text: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                selected: sel,
                labelFor: (d) => _bucketLabel(context, d, s.monthly),
              ),
            ),
          ),
          if (sel != null)
            Positioned(
              left: (axisW + slot * sel + slot / 2 - 70).clamp(0, c.maxWidth - 140),
              top: 0,
              child: IgnorePointer(
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onInverseSurface),
                      child: SizedBox(
                        width: 120,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(_bucketLabel(context, s.buckets[sel].start, s.monthly),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${context.l.statsEaten}: ${s.buckets[sel].eaten}'),
                          Text('${context.l.statsThrown}: ${s.buckets[sel].discarded}'),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.stats,
    required this.maxV,
    required this.axisW,
    required this.labelH,
    required this.eaten,
    required this.thrown,
    required this.surface,
    required this.grid,
    required this.text,
    required this.selected,
    required this.labelFor,
  });

  final Stats stats;
  final int maxV;
  final double axisW, labelH;
  final Color eaten, thrown, surface, grid;
  final TextStyle text;
  final int? selected;
  final String Function(DateTime) labelFor;

  void _text(Canvas c, String s, Offset at, {TextAlign align = TextAlign.center, double width = 40}) {
    final tp = TextPainter(text: TextSpan(text: s, style: text), textDirection: TextDirection.ltr, textAlign: align)
      ..layout(minWidth: width, maxWidth: width);
    tp.paint(c, at - Offset(align == TextAlign.center ? width / 2 : (align == TextAlign.right ? width : 0), tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - labelH - 8;
    final top = 8.0;
    final n = stats.buckets.length;
    final slot = (size.width - axisW) / n;
    final niceMax = _nice(maxV);
    double y(num v) => top + plotH - plotH * v / niceMax;

    // Recessive hairline grid + y labels (0, half, max).
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0, niceMax ~/ 2, niceMax]) {
      canvas.drawLine(Offset(axisW, y(v)), Offset(size.width, y(v)), gridPaint);
      _text(canvas, '$v', Offset(axisW - 6, y(v)), align: TextAlign.right, width: axisW - 6);
    }

    final barW = (slot * 0.6).clamp(4.0, 24.0);
    final labelEvery = (n / 6).ceil();
    for (var i = 0; i < n; i++) {
      final b = stats.buckets[i];
      final cx = axisW + slot * i + slot / 2;
      final dim = selected != null && selected != i;
      final base = y(0);
      final eTop = y(b.eaten);
      final dTop = y(b.eaten + b.discarded);
      const r = Radius.circular(4);
      final eatenPaint = Paint()..color = dim ? eaten.withValues(alpha: 0.35) : eaten;
      final thrownPaint = Paint()..color = dim ? thrown.withValues(alpha: 0.35) : thrown;
      if (b.eaten > 0) {
        // Square at the baseline; rounded only if it is the top segment.
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTRB(cx - barW / 2, eTop, cx + barW / 2, base),
              topLeft: b.discarded == 0 ? r : Radius.zero, topRight: b.discarded == 0 ? r : Radius.zero),
          eatenPaint,
        );
      }
      if (b.discarded > 0) {
        final bottom = b.eaten > 0 ? eTop - 2 : base; // 2px surface gap between segments
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTRB(cx - barW / 2, dTop, cx + barW / 2, bottom), topLeft: r, topRight: r),
          thrownPaint,
        );
      }
      if (i % labelEvery == 0 || i == n - 1) {
        _text(canvas, labelFor(b.start), Offset(cx, size.height - labelH / 2), width: slot * labelEvery);
      }
    }
  }

  static int _nice(int v) {
    if (v <= 4) return 4;
    for (final step in [5, 10, 20, 25, 50, 100]) {
      if (v <= step * 4) return ((v + step - 1) ~/ step) * step;
    }
    return ((v + 99) ~/ 100) * 100;
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) => old.stats != stats || old.selected != selected || old.eaten != eaten;
}

/// Single series → no legend; the section title names it. Value at the end.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.categories});

  final List<CategoryWaste> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _Viz.thrown(theme.brightness);
    final max = categories.first.count;
    return Column(children: [
      for (final c in categories)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 120,
              child: Text('${categoryById(c.categoryId).emoji} ${categoryLabel(context.l, c.categoryId)}',
                  overflow: TextOverflow.ellipsis, maxLines: 1, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (_, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: (box.maxWidth - 64) * c.count / max + 2,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                c.value > 0 ? '${c.count}× · ${c.value.round()} Kč' : '${c.count}×',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _TipCard extends ConsumerWidget {
  const _TipCard({required this.tip});

  final StatsTip tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final (emoji, text) = switch (tip.kind) {
      TipKind.great => ('🏆', l.tipGreat),
      TipKind.improving => ('📉', l.tipImproving),
      TipKind.topCategory => ('💡', l.tipTopCategory(categoryLabel(l, tip.categoryId ?? 'other').toLowerCase())),
      TipKind.forgotten => ('⏰', l.tipForgotten),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
          if (tip.kind == TipKind.topCategory)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(l.tipSetEarlier),
                onPressed: () async {
                  final user = ref.read(userProvider).value;
                  if (user == null) return;
                  await ref.read(repositoryProvider).saveNotificationRule(
                      user.uid, NotificationRule(scope: RuleScope.category, targetId: tip.categoryId, daysBefore: 3));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l.notifications}: ${l.daysBefore(3)}')));
                  }
                },
              ),
            ),
        ]),
      ),
    );
  }
}
