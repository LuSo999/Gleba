import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../app_state.dart';
import '../labels.dart';

String aiFeatureLabel(BuildContext context, AiFeature f) => switch (f) {
      AiFeature.receipt => context.l.aiFeatureReceipt,
      AiFeature.recipe => context.l.aiFeatureRecipe,
      AiFeature.product => context.l.aiFeatureProduct,
      AiFeature.date => context.l.aiFeatureDate,
    };

class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(aiSettingsProvider);
    final household = ref.watch(activeHouseholdProvider);
    final ai = ref.watch(aiServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.aiTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(l.aiIntro)),
          for (final p in AiProvider.values)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                title: Text(aiProviderNames[p]!),
                subtitle: Text([
                  if (settings.deviceKeys[p] case final k?) '${l.aiOnDevice} · ${k.model}',
                  if (household?.aiShared[p.name] case final m?) '${l.aiSharedHousehold} · $m',
                ].join('\n').ifEmpty(l.aiNotSet)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editKey(context, ref, p),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            child: Text(l.aiFeatures, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          for (final f in AiFeature.values)
            ListTile(
              title: Text(aiFeatureLabel(context, f)),
              trailing: DropdownButton<AiProvider?>(
                value: settings.features[f],
                onChanged: (p) => ref.read(aiSettingsProvider.notifier).setFeature(f, p),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.aiAuto)),
                  for (final p in ai.availableProviders)
                    DropdownMenuItem(value: p, child: Text(aiProviderNames[p]!.split(' ').last)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editKey(BuildContext context, WidgetRef ref, AiProvider p) async {
    final l = context.l;
    final settings = ref.read(aiSettingsProvider);
    final shared = ref.read(activeHouseholdProvider)?.aiShared[p.name];
    final keyCtl = TextEditingController();
    final modelCtl = TextEditingController(text: settings.deviceKeys[p]?.model ?? shared ?? defaultAiModels[p]);
    var share = settings.deviceKeys[p] == null && shared != null;
    final canShare = !ref.read(isDemoProvider);
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(aiProviderNames[p]!),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: keyCtl,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l.aiKey),
                ),
                const SizedBox(height: 12),
                TextField(controller: modelCtl, decoration: InputDecoration(labelText: l.aiModel)),
                const SizedBox(height: 8),
                SelectableText(l.aiGetKey(aiKeyUrls[p]!), style: Theme.of(ctx).textTheme.bodySmall),
                if (canShare) ...[
                  const SizedBox(height: 8),
                  RadioGroup<bool>(
                    groupValue: share,
                    onChanged: (v) => setState(() => share = v ?? false),
                    child: Column(children: [
                      RadioListTile(value: false, title: Text(l.aiDeviceOnly), contentPadding: EdgeInsets.zero),
                      RadioListTile(
                        value: true,
                        title: Text(l.aiShareHousehold),
                        subtitle: Text(l.aiShareHint),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (settings.deviceKeys[p] != null || shared != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: Text(l.aiRemove)),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(l.save)),
          ],
        ),
      ),
    );
    if (result == null) return;
    final notifier = ref.read(aiSettingsProvider.notifier);
    final ai = ref.read(aiServiceProvider);
    final model = modelCtl.text.trim().isEmpty ? defaultAiModels[p]! : modelCtl.text.trim();
    try {
      if (result == 'remove') {
        await notifier.setDeviceKey(p, null, model);
        if (shared != null) await ai.setSharedKey(p, null, model);
      } else if (keyCtl.text.trim().isNotEmpty) {
        if (share) {
          await ai.setSharedKey(p, keyCtl.text.trim(), model);
          await notifier.setDeviceKey(p, null, model);
        } else {
          await notifier.setDeviceKey(p, keyCtl.text.trim(), model);
        }
      }
    } on AiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.aiError(e.message))));
    }
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
