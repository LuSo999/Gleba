import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/eaters.dart';
import '../../domain/history.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../labels.dart';

/// Colours of the people on the share bar (desaturated, readable with white).
const _personColors = [Color(0xFF4F86C6), Color(0xFFC9718F), Color(0xFF3E9C84), Color(0xFFC98F3A), Color(0xFF8A70C2)];
const _othersColor = Color(0xFF8C969E);

class Eater {
  const Eater(this.id, this.name, this.color);

  final String id;
  final String name;
  final Color color;
}

/// The members of [h] (me first) and "Others".
List<Eater> eatersOf(Household h, String myUid, AppLocalizations l) {
  final ids = [myUid, ...h.memberIds.where((m) => m != myUid)];
  return [
    for (var i = 0; i < ids.length; i++)
      Eater(
        ids[i],
        ids[i] == myUid ? l.whoMe : (h.memberNames[ids[i]] ?? l.whoMember),
        _personColors[i % _personColors.length],
      ),
    Eater(othersEater, l.whoOthers, _othersColor),
  ];
}

/// "Who ate it?" – big tiles to tick, and a bar with N-1 handles to split it.
/// Returns uid → share, or null when dismissed.
Future<Map<String, double>?> showWhoAteSheet(
  BuildContext context, {
  required Household household,
  required String myUid,
  required String title,
  double? grams,
}) =>
    showModalBottomSheet<Map<String, double>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => WhoAteSheet(household: household, myUid: myUid, title: title, grams: grams),
    );

class WhoAteSheet extends ConsumerStatefulWidget {
  const WhoAteSheet({super.key, required this.household, required this.myUid, required this.title, this.grams});

  final Household household;
  final String myUid;
  final String title;
  final double? grams;

  @override
  ConsumerState<WhoAteSheet> createState() => _WhoAteSheetState();
}

class _WhoAteSheetState extends ConsumerState<WhoAteSheet> {
  late List<String> _chosen = [widget.myUid];
  List<double> _cuts = const [];

  void _toggle(List<Eater> all, String id) => setState(() {
        final on = !_chosen.contains(id);
        // Keep the order of the tiles.
        _chosen = [for (final e in all) if (e.id == id ? on : _chosen.contains(e.id)) e.id];
        _cuts = evenCuts(_chosen.length);
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final all = eatersOf(widget.household, widget.myUid, l);
    final chosen = [for (final id in _chosen) all.firstWhere((e) => e.id == id)];
    final shares = sharesFromCuts(_cuts);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.whoAte, style: theme.textTheme.titleLarge),
            Text(
              [widget.title, if (widget.grams != null) '${widget.grams!.round()} g'].join(' · '),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: all.length <= 4 ? all.length.clamp(2, 4) : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.95,
              children: [
                for (final e in all)
                  _PersonTile(eater: e, selected: _chosen.contains(e.id), onTap: () => _toggle(all, e.id)),
              ],
            ),
            if (chosen.length > 1) ...[
              const SizedBox(height: 18),
              ShareBar(
                colors: [for (final e in chosen) e.color],
                cuts: _cuts,
                onChanged: (i, v) => setState(() => _cuts = moveCut(_cuts, i, v)),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < chosen.length; i++)
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '● ', style: TextStyle(color: chosen[i].color)),
                      TextSpan(
                        text: '${chosen[i].name} '
                            '${widget.grams == null ? '${(shares[i] * 100).round()} %' : '${(shares[i] * widget.grams!).round()} g'}',
                      ),
                    ]), style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, eatersFrom(_chosen, _cuts)),
              child: Text(l.done),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.eater, required this.selected, required this.onTap});

  final Eater eater;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = eater.color;
    return Semantics(
      checked: selected,
      button: true,
      label: eater.name,
      child: Material(
        color: selected ? c.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? c : theme.colorScheme.outlineVariant, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: c,
                      child: Text(
                        eater.id == othersEater ? '+' : eater.name.characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(eater.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: selected ? c : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bar split into coloured parts by N-1 draggable handles.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.colors, required this.cuts, required this.onChanged});

  final List<Color> colors;
  final List<double> cuts;
  final void Function(int index, double value) onChanged;

  static const _h = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shares = sharesFromCuts(cuts);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: _h + 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              height: _h,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_h / 2),
                child: Row(
                  children: [
                    for (var i = 0; i < shares.length; i++)
                      Expanded(
                        flex: (shares[i] * 1000).round(),
                        child: Container(
                          color: colors[i],
                          alignment: Alignment.center,
                          child: FittedBox(
                            child: Text('${(shares[i] * 100).round()} %',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < cuts.length; i++)
              Positioned(
                left: cuts[i] * w - 22,
                top: 0,
                width: 44,
                height: _h + 12,
                child: Semantics(
                  slider: true,
                  value: '${(cuts[i] * 100).round()} %',
                  increasedValue: '${((cuts[i] + 0.05) * 100).round()} %',
                  decreasedValue: '${((cuts[i] - 0.05) * 100).round()} %',
                  onIncrease: () => onChanged(i, cuts[i] + 0.05),
                  onDecrease: () => onChanged(i, cuts[i] - 0.05),
                  child: GestureDetector(
                    key: ValueKey('cut$i'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      onChanged(i, box.globalToLocal(d.globalPosition).dx / w);
                    },
                    child: Center(
                      child: Container(
                        width: 8,
                        height: _h + 12,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: theme.colorScheme.onSurface, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
