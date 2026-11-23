import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_client.dart';
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

const _providerEmoji = {AiProvider.gemini: '✨', AiProvider.openai: '🟢', AiProvider.anthropic: '🟠'};

/// Keys per provider (checked against the provider, with its model list),
/// then per feature: which provider and which model.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _loading = <AiProvider>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  /// Checks every configured key once per session.
  void _refreshAll() {
    final ai = ref.read(aiServiceProvider);
    final s = ref.read(aiSettingsProvider);
    for (final p in ai.availableProviders) {
      if (!s.models.containsKey(p)) _load(p);
    }
  }

  Future<void> _load(AiProvider p) async {
    setState(() => _loading.add(p));
    try {
      await ref.read(aiServiceProvider).loadModels(p);
    } catch (_) {
      // shown via keyErrors
    } finally {
      if (mounted) setState(() => _loading.remove(p));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final settings = ref.watch(aiSettingsProvider);
    final household = ref.watch(activeHouseholdProvider);
    final ai = ref.watch(aiServiceProvider);
    final theme = Theme.of(context);
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.aiTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(l.aiIntro)),
          header(l.aiProviders),
          for (final p in AiProvider.values)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Text(_providerEmoji[p]!, style: const TextStyle(fontSize: 24)),
                title: Text(aiProviderNames[p]!),
                subtitle: Text([
                  if (settings.deviceKeys.containsKey(p)) l.aiOnDevice,
                  if (household?.aiShared.containsKey(p.name) ?? false) l.aiSharedHousehold,
                  if (!ai.available(p)) l.aiNotSet,
                  if (_loading.contains(p))
                    l.aiKeyChecking
                  else if (settings.keyErrors[p] case final e?)
                    l.aiKeyBad(e)
                  else if (settings.models[p] case final m?)
                    l.aiKeyOk(m.length),
                ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editKey(p),
              ),
            ),
          header(l.aiFeatures),
          if (ai.availableProviders.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l.aiNoKeyYet))
          else
            for (final f in AiFeature.values) _FeatureCard(feature: f, onReload: _load),
        ],
      ),
    );
  }

  Future<void> _editKey(AiProvider p) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _KeySheet(provider: p),
    );
    if (saved == true) _load(p);
  }
}

/// Provider + model for one feature.
class _FeatureCard extends ConsumerWidget {
  const _FeatureCard({required this.feature, required this.onReload});

  final AiFeature feature;
  final Future<void> Function(AiProvider) onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(aiSettingsProvider);
    final ai = ref.watch(aiServiceProvider);
    final provider = ai.providerFor(feature)!;
    final models = settings.models[provider] ?? const <AiModelInfo>[];
    final recommended = recommendedModel(provider, tierOf(feature), models);
    final chosen = settings.features[feature] == provider ? settings.featureModels[feature] : null;
    final notifier = ref.read(aiSettingsProvider.notifier);

    // null = recommended; a listed id; or a custom id not in the list.
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem(value: null, child: Text('★ ${l.aiRecommended}${recommended == null ? '' : ' · $recommended'}')),
      for (final m in models)
        DropdownMenuItem(value: m.id, child: Text('${m.id == recommended ? '★ ' : ''}${m.label}', overflow: TextOverflow.ellipsis)),
      if (chosen != null && !models.any((m) => m.id == chosen)) DropdownMenuItem(value: chosen, child: Text(chosen)),
      DropdownMenuItem(value: '__other', child: Text(l.aiOther)),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(aiFeatureLabel(context, feature), style: Theme.of(context).textTheme.titleSmall),
          Text(tierOf(feature) == AiTier.fast ? l.aiTierFast : l.aiTierSmart, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiProvider>(
            initialValue: provider,
            decoration: InputDecoration(labelText: l.aiProvider, isDense: true),
            items: [
              for (final p in ai.availableProviders)
                DropdownMenuItem(value: p, child: Text('${_providerEmoji[p]} ${aiProviderNames[p]}')),
            ],
            onChanged: (p) {
              notifier.setFeature(feature, p);
              if (p != null && !settings.models.containsKey(p)) onReload(p);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            key: ValueKey('$provider/${models.length}/$chosen'),
            initialValue: chosen,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Model', isDense: true),
            items: items,
            onChanged: (v) async {
              if (v != '__other') {
                if (settings.features[feature] != provider) notifier.setFeature(feature, provider);
                notifier.setFeatureModel(feature, v);
                return;
              }
              final ctl = TextEditingController(text: chosen ?? recommended ?? '');
              final custom = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.aiOtherModel),
                  content: TextField(controller: ctl, autofocus: true, autocorrect: false),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(l.save)),
                  ],
                ),
              );
              if (custom != null && custom.isNotEmpty) {
                if (settings.features[feature] != provider) notifier.setFeature(feature, provider);
                notifier.setFeatureModel(feature, custom);
              }
            },
          ),
        ]),
      ),
    );
  }
}

/// Enter / check / save / remove a key. The key is verified against the
/// provider (by listing its models) before it's stored.
class _KeySheet extends ConsumerStatefulWidget {
  const _KeySheet({required this.provider});

  final AiProvider provider;

  @override
  ConsumerState<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends ConsumerState<_KeySheet> {
  final _key = TextEditingController();
  late bool _share =
      !ref.read(aiSettingsProvider).deviceKeys.containsKey(widget.provider) &&
          (ref.read(activeHouseholdProvider)?.aiShared.containsKey(widget.provider.name) ?? false);
  bool _busy = false;
  String? _status;
  bool _ok = false;
  List<AiModelInfo> _models = const [];

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<bool> _check() async {
    setState(() {
      _busy = true;
      _status = context.l.aiKeyChecking;
    });
    try {
      final models = await DirectAiClient().listModels(widget.provider, _key.text.trim());
      if (!mounted) return false;
      setState(() {
        _ok = true;
        _models = models;
        _status = context.l.aiKeyOk(models.length);
      });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _status = context.l.aiKeyBad('$e');
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_ok && !await _check()) return;
    final p = widget.provider;
    final key = _key.text.trim();
    final model = recommendedModel(p, AiTier.smart, _models) ?? defaultAiModels[p]!;
    final notifier = ref.read(aiSettingsProvider.notifier);
    final ai = ref.read(aiServiceProvider);
    setState(() => _busy = true);
    try {
      if (_share) {
        await ai.setSharedKey(p, key, model);
        await notifier.setDeviceKey(p, null, model);
      } else {
        await notifier.setDeviceKey(p, key, model);
      }
      if (mounted) Navigator.pop(context, true);
    } on AiException catch (e) {
      if (mounted) setState(() => _status = context.l.aiError(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final p = widget.provider;
    await ref.read(aiSettingsProvider.notifier).setDeviceKey(p, null, defaultAiModels[p]!);
    if (ref.read(activeHouseholdProvider)?.aiShared.containsKey(p.name) ?? false) {
      await ref.read(aiServiceProvider).setSharedKey(p, null, defaultAiModels[p]!);
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = widget.provider;
    final hasKey = ref.read(aiServiceProvider).available(p);
    final canShare = !ref.read(isDemoProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${_providerEmoji[p]} ${aiProviderNames[p]}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          SelectableText(l.aiGetKey(aiKeyUrls[p]!), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.aiKey,
              suffixIcon: IconButton(
                tooltip: l.aiCheck,
                icon: const Icon(Icons.verified_outlined),
                onPressed: _busy || _key.text.trim().isEmpty ? null : _check,
              ),
            ),
            onChanged: (_) => setState(() {
              _ok = false;
              _status = null;
            }),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: TextStyle(color: _ok ? Colors.green.shade700 : null)),
            ),
          if (canShare) ...[
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _share,
              onChanged: (v) => setState(() => _share = v ?? false),
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || _key.text.trim().isEmpty ? null : _save,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l.save),
          ),
          if (hasKey) TextButton(onPressed: _busy ? null : _remove, child: Text(l.aiRemove)),
        ]),
      ),
    );
  }
}
