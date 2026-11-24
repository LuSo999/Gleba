import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/batch.dart';
import '../../domain/freshness.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/burst.dart';
import '../widgets/edit_item_sheet.dart';
import 'batch_job.dart';

/// Everything from the series in one list: tick, fix, save all.
class BatchReviewScreen extends ConsumerWidget {
  const BatchReviewScreen({super.key});

  Future<void> _addReceipt(BuildContext context, WidgetRef ref) async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (photo != null) await ref.read(batchJobProvider.notifier).addReceipt(await photo.readAsBytes());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    ref.watch(batchJobProvider);
    final job = ref.read(batchJobProvider.notifier);
    final rows = job.rows();
    final chosen = rows.where((r) => job.isSelected(r) && !r.busy).length;
    final total = job.products.length;
    final done = total - job.processing;
    final unpaired = job.receiptState == ReceiptState.done && job.pairingOn
        ? job.products.where((p) => !job.pairing.containsKey(p.id)).length
        : 0;

    return Scaffold(
      appBar: AppBar(title: Text(l.batchReviewTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
        children: [
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Text('🧾', style: TextStyle(fontSize: 26)),
              title: Text(switch (job.receiptState) {
                ReceiptState.none => l.batchNoReceipt,
                ReceiptState.reading => l.receiptReading,
                ReceiptState.done => l.batchReceiptPaired(job.pairing.length, total, rows.where((r) => r.fromReceiptOnly).length),
                ReceiptState.failed => l.aiError(job.receiptError ?? ''),
              }),
              subtitle: job.receiptState == ReceiptState.none ? Text(l.batchReceiptHint) : null,
              trailing: switch (job.receiptState) {
                ReceiptState.reading => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                ReceiptState.done => const Icon(Icons.chevron_right),
                _ => const Icon(Icons.add_a_photo_outlined),
              },
              onTap: switch (job.receiptState) {
                ReceiptState.reading => null,
                ReceiptState.done => () => context.push('/batch/pair'),
                _ => () => _addReceipt(context, ref),
              },
            ),
          ),
          if (job.processing > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.batchProcessed(done, total), style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: total == 0 ? null : done / total, borderRadius: BorderRadius.circular(3)),
              ]),
            ),
          if (unpaired > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(l.batchUnpaired(unpaired), style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 6),
          for (final r in rows) _RowTile(row: r),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.canPop() ? context.pop() : context.go('/batch'),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(l.batchMorePhotos),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: chosen == 0
                    ? null
                    : () async {
                        final n = await job.save();
                        if (!context.mounted) return;
                        showBurst(context, '🛒', particles: const ['✨', '🧊']);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.receiptSaved(n))));
                        context.go('/');
                      },
                icon: const Icon(Icons.check),
                label: Text(l.batchSave(chosen)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RowTile extends ConsumerWidget {
  const _RowTile({required this.row});

  final ReviewRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final job = ref.read(batchJobProvider.notifier);
    final r = row;
    final p = r.product;
    final selected = job.isSelected(r);
    final now = DateTime.now();
    final color = GlebaColors.freshness(freshnessOf(r.item, now), theme.brightness);
    final estimate = r.dateSource == DateSource.estimate;
    final notFood = r.lineIndex != null && !job.receiptLines[r.lineIndex!].isFood;

    Widget tag(String text, {Color? c}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: (c ?? theme.colorScheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: c ?? theme.colorScheme.primary)),
        );
    const receiptColor = Color(0xFF8A70C2);
    final warn = GlebaColors.freshness(Freshness.soon, theme.brightness);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: r.busy
            ? null
            : () async {
                final edited = await showEditItemSheet(context, r.item);
                if (edited != null) job.edit(r.key, edited);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 12, 6),
          child: Row(children: [
            Checkbox(value: selected && !r.busy, onChanged: r.busy ? null : (v) => job.toggle(r.key, v ?? false)),
            SizedBox(
              width: 34,
              child: r.busy
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Text(categoryById(r.item.categoryId).emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  r.busy && r.item.name.isEmpty
                      ? l.batchReading
                      : (r.item.name.isEmpty ? l.batchUnknownProduct : r.item.name),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Wrap(spacing: 6, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (notFood)
                    Text(l.batchNotFood, style: theme.textTheme.bodySmall)
                  else
                    Text(
                      estimate
                          ? l.batchEstimate(formatDate(context, r.item.expiryDate))
                          : '${dateTypeLabel(l, r.item.dateType)} ${formatDate(context, r.item.expiryDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: estimate ? warn : color,
                        fontWeight: estimate ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  Text(
                    [
                      '${r.item.quantity == r.item.quantity.roundToDouble() ? r.item.quantity.round() : r.item.quantity} ${r.item.unit}',
                      if (r.item.price != null) '${r.item.price!.toStringAsFixed(2)} Kč',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (p?.ean != null) tag('EAN'),
                  if (p?.productSource == ProductSource.ai) tag(l.batchTagAiProduct),
                  if (r.dateSource == DateSource.ai) tag(l.batchTagAiDate),
                  if (r.dateSource == DateSource.code) tag(l.batchTagCodeDate),
                  if (r.onReceipt && !r.fromReceiptOnly) tag(l.batchTagReceipt, c: receiptColor),
                  if (r.fromReceiptOnly) tag(l.batchTagReceiptOnly, c: receiptColor),
                  if (p != null && job.receiptState == ReceiptState.done && job.pairingOn && !r.onReceipt)
                    tag(l.batchTagNotOnReceipt, c: warn),
                  if (p?.productState == ShotState.failed) tag(l.batchTagUnknown, c: warn),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Which photo belongs to which receipt line.
class BatchPairScreen extends ConsumerWidget {
  const BatchPairScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    ref.watch(batchJobProvider);
    final job = ref.read(batchJobProvider.notifier);
    final pairs = job.pairing;

    Future<void> choose(BatchProduct p) async {
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(p.name),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, -1), child: Text(l.batchNotOnReceipt)),
            for (var i = 0; i < job.receiptLines.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, i),
                child: Text([
                  job.receiptLines[i].name,
                  if (job.receiptLines[i].price != null) '${job.receiptLines[i].price!.toStringAsFixed(2)} Kč',
                ].join(' · ')),
              ),
          ],
        ),
      );
      if (picked != null) job.setPair(p.id, picked < 0 ? null : picked);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.batchPairTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SwitchListTile(
            title: Text(l.batchPairOn),
            subtitle: Text(l.batchPairOnText),
            value: job.pairingOn,
            onChanged: job.setPairingOn,
          ),
          const Divider(),
          for (final p in job.products)
            ListTile(
              leading: Text(categoryById(p.categoryId).emoji, style: const TextStyle(fontSize: 24)),
              title: Text(p.name.isEmpty ? l.batchUnknownProduct : p.name),
              subtitle: Text(
                pairs[p.id] == null ? l.batchNotOnReceipt : '⟷ ${job.receiptLines[pairs[p.id]!].name}',
                style: TextStyle(
                  color: pairs[p.id] == null
                      ? GlebaColors.freshness(Freshness.soon, theme.brightness)
                      : const Color(0xFF8A70C2),
                ),
              ),
              trailing: TextButton(onPressed: job.pairingOn ? () => choose(p) : null, child: Text(l.batchChange)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: () => context.pop(), child: Text(l.done)),
        ),
      ),
    );
  }
}
