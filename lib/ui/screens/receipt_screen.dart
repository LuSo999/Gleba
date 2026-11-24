import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../ai/image_split.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../widgets/burst.dart';

class ReceiptDraftLine {
  ReceiptDraftLine(this.line)
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

enum ReceiptStage { idle, preparing, working, parsing, done, error }

class ReceiptJob {
  const ReceiptJob({
    this.stage = ReceiptStage.idle,
    this.startedAt,
    this.lines,
    this.error,
    this.saving = false,
    this.retry,
    this.canRetry = false,
    this.details,
  });

  final ReceiptStage stage;
  final DateTime? startedAt;
  final List<ReceiptDraftLine>? lines;

  /// 'empty', 'no-provider' or the AI error message.
  final String? error;
  final bool saving;

  /// Set while the AI is retried or another model is tried.
  final AiRetryNote? retry;

  /// After an error: the last photo can be sent again.
  final bool canRetry;

  /// After an error: which models answered what (troubleshooting).
  final String? details;

  bool get busy => stage == ReceiptStage.preparing || stage == ReceiptStage.working || stage == ReceiptStage.parsing;
}

/// Lives outside the screen, so reading a receipt survives rotating the
/// phone, leaving the screen, or the activity being recreated: the result
/// is waiting when you come back.
class ReceiptJobNotifier extends Notifier<ReceiptJob> {
  @override
  ReceiptJob build() => const ReceiptJob();

  void reset() => state = const ReceiptJob();

  /// Line edits mutate the drafts in place; this just redraws.
  void touch() => state = ReceiptJob(stage: state.stage, startedAt: state.startedAt, lines: state.lines, error: state.error);

  void saving(bool v) =>
      state = ReceiptJob(stage: state.stage, startedAt: state.startedAt, lines: state.lines, error: state.error, saving: v);

  Uint8List? _lastPhoto;
  String _lastLang = 'cs';

  /// Sends the last photo again (after an error).
  Future<void> retry() async {
    final bytes = _lastPhoto;
    if (bytes != null && !state.busy) await _run(bytes, _lastLang);
  }

  Future<void> start(XFile photo, String lang) async {
    if (state.busy) return;
    state = ReceiptJob(stage: ReceiptStage.preparing, startedAt: DateTime.now());
    try {
      await _run(await photo.readAsBytes(), lang);
    } catch (e) {
      state = ReceiptJob(stage: ReceiptStage.error, error: '$e');
    }
  }

  Future<void> _run(Uint8List bytes, String lang) async {
    _lastPhoto = bytes;
    _lastLang = lang;
    final ai = ref.read(aiServiceProvider);
    if (!ai.enabledFor(AiFeature.receipt)) {
      state = const ReceiptJob(stage: ReceiptStage.error, error: 'no-provider');
      return;
    }
    final started = DateTime.now();
    final log = StringBuffer();
    try {
      state = ReceiptJob(stage: ReceiptStage.working, startedAt: started);
      final image = AiImage.detect(bytes);
      final parts = await compute(splitTallImage, image);
      log.writeln('${image.mime}, ${bytes.length ~/ 1024} kB, ${parts.length} part(s)');
      final lines = await ai.runParsed(
        AiFeature.receipt,
        receiptRequest(parts, lang),
        (text) {
          final lines = parseReceipt(text);
          // Nothing found is usually the model's slip: ask the next one.
          if (lines.isEmpty) throw const AiException('empty', transient: true);
          return lines;
        },
        onRetry: (note) => state = ReceiptJob(stage: ReceiptStage.working, startedAt: DateTime.now(), retry: note),
        onAnswer: (a, text) => log.writeln('\n${a.model ?? a.provider.name}:\n'
            '${text.length > 600 ? '${text.substring(0, 600)}…' : text}'),
      );
      state = ReceiptJob(stage: ReceiptStage.done, lines: [for (final r in lines) ReceiptDraftLine(r)]);
    } catch (e) {
      log.writeln('\n$e');
      state = ReceiptJob(stage: ReceiptStage.error, error: '$e', canRetry: true, details: log.toString());
    }
  }
}

final receiptJobProvider = NotifierProvider<ReceiptJobNotifier, ReceiptJob>(ReceiptJobNotifier.new);

/// Photograph a receipt → AI lists the items → review → add them all at once.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> with SingleTickerProviderStateMixin {
  // Ticks while the AI works, to move the progress bar and the seconds.
  late final _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    // Android may kill the app while the camera is open; recover that photo.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      ImagePicker().retrieveLostData().then((r) {
        final f = r.file;
        if (f != null && mounted) _start(f);
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start(XFile photo) =>
      ref.read(receiptJobProvider.notifier).start(photo, Localizations.localeOf(context).languageCode);

  Future<void> _pick(ImageSource source) async {
    final photo = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (photo != null && mounted) _start(photo);
  }

  Future<void> _save() async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    final job = ref.read(receiptJobProvider);
    final lines = job.lines?.where((x) => x.selected).toList() ?? const [];
    if (h == null || user == null || lines.isEmpty || job.saving) return;
    final notifier = ref.read(receiptJobProvider.notifier)..saving(true);
    final repo = ref.read(repositoryProvider);
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
    notifier.reset();
    if (!mounted) return;
    showBurst(context, '🧾', particles: const ['✨', '🛒'], enabled: ref.read(settingsProvider).animations);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.receiptSaved(lines.length))));
    Navigator.pop(context);
  }

  /// Honest progress: known steps, and while the AI works an easing curve
  /// that approaches but never reaches the end before the answer is in.
  Widget _progress(BuildContext context, ReceiptJob job) {
    final l = context.l;
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final secs = job.startedAt == null ? 0 : DateTime.now().difference(job.startedAt!).inMilliseconds / 1000;
        final (value, label) = switch (job.stage) {
          ReceiptStage.preparing => (0.05, l.receiptStepPhoto),
          ReceiptStage.working when secs < 2 => (0.08 + secs * 0.02, l.receiptStepSending),
          ReceiptStage.working => (
              0.12 + 0.8 * (1 - exp(-(secs - 2) / 14)),
              job.retry == null
                  ? l.receiptStepReading(secs.round())
                  : '${job.retry!.retry > 0 ? l.aiRetrying : l.aiTryingOther(job.retry!.attempt.model ?? aiProviderNames[job.retry!.attempt.provider]!)}'
                      '\n${l.receiptStepReading(secs.round())}'
            ),
          _ => (0.95, l.receiptStepParsing),
        };
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _Spinning(emoji: '🧾'),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: value, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.receiptKeepsGoing, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final job = ref.watch(receiptJobProvider);
    final lines = job.lines;
    final selected = lines?.where((x) => x.selected).length ?? 0;
    if (job.busy && !_ticker.isAnimating) _ticker.repeat();
    if (!job.busy && _ticker.isAnimating) _ticker.stop();
    final error = switch (job.error) {
      null => null,
      'empty' => l.receiptEmpty,
      'no-provider' => l.aiNoProvider,
      'invalid-json' => l.aiBadAnswer,
      final e => l.aiError(e),
    };
    void setState(VoidCallback f) {
      f();
      ref.read(receiptJobProvider.notifier).touch();
    }

    Widget body;
    if (job.busy || job.saving) {
      body = Center(child: _progress(context, job));
    } else if (lines == null || lines.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🧾', style: TextStyle(fontSize: 72)),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
              if (job.details case final d?)
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l.aiDetails),
                      content: SingleChildScrollView(
                        child: SelectableText(d, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).closeButtonLabel))],
                    ),
                  ),
                  child: Text(l.aiDetails),
                ),
            ],
            const SizedBox(height: 24),
            if (job.canRetry) ...[
              FilledButton.tonalIcon(
                onPressed: () => ref.read(receiptJobProvider.notifier).retry(),
                icon: const Icon(Icons.refresh),
                label: Text(l.receiptRetry),
              ),
              const SizedBox(height: 8),
            ],
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
      floatingActionButton: lines != null && lines.isNotEmpty && !job.busy && !job.saving
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
