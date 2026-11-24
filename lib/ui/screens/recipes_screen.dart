import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/shelf_life.dart';
import '../labels.dart';
import '../links.dart';
import 'receipt_screen.dart' show AiThinking;

/// Pick ingredients (urgent ones preselected) → AI suggests recipes,
/// or copy a ready-made prompt to paste into any AI chat.
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  Set<String>? _selected;
  final _wishes = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _wishes.dispose();
    super.dispose();
  }

  String _prompt() {
    final now = DateTime.now();
    final items = (ref.read(itemsProvider).value ?? const []).where((i) => _selected!.contains(i.id)).toList();
    return recipePrompt(sortByUrgency(items, now), _wishes.text, Localizations.localeOf(context).languageCode, now);
  }

  Future<void> _suggest() async {
    final l = context.l;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final text = await ref.read(aiServiceProvider).run(AiFeature.recipe, AiRequest(prompt: _prompt()));
      setState(() => _result = text.trim());
    } catch (e) {
      setState(() => _error = l.aiError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = DateTime.now();
    final items = sortByUrgency(ref.watch(itemsProvider).value ?? const [], now);
    _selected ??= {
      ...items.where((i) => freshnessOf(i, now) != Freshness.fresh).map((i) => i.id),
      if (items.every((i) => freshnessOf(i, now) == Freshness.fresh)) ...items.take(5).map((i) => i.id),
    };
    final aiOn = ref.watch(aiServiceProvider).enabledFor(AiFeature.recipe);

    return Scaffold(
      appBar: AppBar(title: Text(l.recipesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.recipesPick, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in items)
              FilterChip(
                avatar: Text(categoryById(i.categoryId).emoji),
                label: Text(i.name),
                selected: _selected!.contains(i.id),
                onSelected: (v) => setState(() => v ? _selected!.add(i.id) : _selected!.remove(i.id)),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(controller: _wishes, decoration: InputDecoration(labelText: l.recipesWishes)),
          const SizedBox(height: 16),
          if (aiOn)
            FilledButton.icon(
              onPressed: _busy || _selected!.isEmpty ? null : _suggest,
              icon: const Text('🍳'),
              label: Text(l.recipesSuggest),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _selected!.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _prompt()));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                  },
            icon: const Icon(Icons.copy),
            label: Text(l.recipesCopy),
          ),
          if (!aiOn) ...[
            const SizedBox(height: 8),
            Text(l.aiNoProvider, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          if (_busy) Center(child: AiThinking(emoji: '🍳', text: l.recipesThinking)),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SelectableText(_result!.replaceAll('**', '').replaceAll(RegExp(r'^#+\s*', multiLine: true), '')),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => reportAiAnswer(_result!),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: Text(l.aiReport),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
