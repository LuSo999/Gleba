import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../widgets/burst.dart';

class _Line {
  _Line(this.line)
      : selected = line.isFood,
        location = suggestLocation(line.categoryId) {
    expiry = suggestExpiry(line.categoryId, location, DateTime.now());
    name = TextEditingController(text: line.name);
  }

  final ReceiptLine line;
  late final TextEditingController name;
  bool selected;
  LocationType location;
  late DateTime expiry;
  bool expiryTouched = false;

  void setCategory(String id) {
    line.categoryId = id;
    location = suggestLocation(id);
    if (!expiryTouched) expiry = suggestExpiry(id, location, DateTime.now());
  }
}

/// Photograph a receipt → AI lists the items → review → add them all at once.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _busy = false;
  String? _error;
  List<_Line>? _lines;

  Future<void> _pick(ImageSource source) async {
    final l = context.l;
    final ai = ref.read(aiServiceProvider);
    final lang = Localizations.localeOf(context).languageCode;
    if (!ai.enabledFor(AiFeature.receipt)) {
      setState(() => _error = l.aiNoProvider);
      return;
    }
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _lines = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      final text = await ai.run(AiFeature.receipt, receiptRequest(AiImage(bytes), lang));
      final lines = parseReceipt(text);
      setState(() {
        _lines = [for (final r in lines) _Line(r)];
        if (lines.isEmpty) _error = l.receiptEmpty;
      });
    } catch (e) {
      setState(() => _error = l.aiError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    final lines = _lines?.where((x) => x.selected).toList() ?? const [];
    if (h == null || user == null || lines.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    setState(() => _busy = true);
    for (final x in lines) {
      await repo.addItem(
        h.id,
        PantryItem(
          id: '',
          name: x.name.text.trim().isEmpty ? x.line.name : x.name.text.trim(),
          categoryId: x.line.categoryId,
          expiryDate: x.expiry,
          locationId: x.location.name,
          locationType: x.location,
          quantity: x.line.quantity,
          unit: x.line.unit,
          price: x.line.price,
          source: ItemSource.receipt,
        ),
        user,
      );
    }
    if (!mounted) return;
    showBurst(context, '🧾', particles: const ['✨', '🛒'], enabled: ref.read(settingsProvider).animations);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.receiptSaved(lines.length))));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final lines = _lines;
    final selected = lines?.where((x) => x.selected).length ?? 0;

    Widget body;
    if (_busy) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Spinning(emoji: '🧾'),
          const SizedBox(height: 16),
          Text(l.receiptReading),
        ]),
      );
    } else if (lines == null || lines.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🧾', style: TextStyle(fontSize: 72)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: Text(l.receiptTake),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l.receiptGallery),
            ),
          ]),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final x = lines[i];
          final cat = categoryById(x.line.categoryId);
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: x.selected, onChanged: (v) => setState(() => x.selected = v ?? false)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: x.name, decoration: const InputDecoration(isDense: true, border: InputBorder.none)),
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          ActionChip(
                            avatar: Text(cat.emoji),
                            label: Text(categoryLabel(l, cat.id)),
                            onPressed: () async {
                              final id = await showDialog<String>(
                                context: context,
                                builder: (ctx) => SimpleDialog(children: [
                                  for (final c in foodCategories)
                                    SimpleDialogOption(
                                      onPressed: () => Navigator.pop(ctx, c.id),
                                      child: Text('${c.emoji}  ${categoryLabel(l, c.id)}'),
                                    ),
                                ]),
                              );
                              if (id != null) setState(() => x.setCategory(id));
                            },
                          ),
                          ActionChip(
                            label: Text(locationLabel(l, x.location)),
                            onPressed: () => setState(() {
                              const order = [LocationType.fridge, LocationType.freezer, LocationType.pantry];
                              x.location = order[(order.indexOf(x.location) + 1) % order.length];
                              if (!x.expiryTouched) x.expiry = suggestExpiry(x.line.categoryId, x.location, DateTime.now());
                            }),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.event, size: 16),
                            label: Text(formatDate(context, x.expiry)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: x.expiry,
                                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                              );
                              if (d != null) {
                                setState(() {
                                  x.expiry = d;
                                  x.expiryTouched = true;
                                });
                              }
                            },
                          ),
                          Text('${_q(x.line.quantity)} ${x.line.unit}'
                              '${x.line.price == null ? '' : ' · ${x.line.price!.toStringAsFixed(2)} Kč'}'),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.receiptTitle)),
      body: body,
      floatingActionButton: lines != null && lines.isNotEmpty && !_busy
          ? FloatingActionButton.extended(
              onPressed: selected == 0 ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(l.receiptSave(selected)),
            )
          : null,
    );
  }

  static String _q(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

/// Fun "thinking" animation: a gently spinning, bouncing emoji.
class _Spinning extends StatefulWidget {
  const _Spinning({required this.emoji});

  final String emoji;

  @override
  State<_Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<_Spinning> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -12 * Curves.easeInOut.transform((_c.value * 2) % 1 < .5 ? (_c.value * 2) % 1 * 2 : 2 - (_c.value * 2) % 1 * 2)),
          child: Transform.rotate(angle: 0.25 * (_c.value < .5 ? _c.value : 1 - _c.value), child: child),
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 72)),
      );
}

/// Exposed for other AI screens.
class AiThinking extends StatelessWidget {
  const AiThinking({super.key, required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        _Spinning(emoji: emoji),
        const SizedBox(height: 16),
        Text(text),
      ]);
}
