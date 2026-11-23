import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/ai_tasks.dart';
import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/meal_plan.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../../domain/shopping.dart';
import '../labels.dart';
import '../widgets/item_sheet.dart' show restock;
import 'receipt_screen.dart' show AiThinking;

String slotLabel(BuildContext context, MealSlot s) => switch (s) {
  MealSlot.breakfast => context.l.slotBreakfast,
  MealSlot.lunch => context.l.slotLunch,
  MealSlot.dinner => context.l.slotDinner,
};

const _slotEmoji = {MealSlot.breakfast: '🥣', MealSlot.lunch: '🍲', MealSlot.dinner: '🍝'};

/// Weekly meal plan shared by the household.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  int _week = 0;
  Stream<List<Meal>>? _stream;
  String? _streamKey;

  DateTime get _monday => weekStart(DateTime.now()).add(Duration(days: 7 * _week));

  Stream<List<Meal>> _meals(String hid) {
    final key = '$hid/${dayKey(_monday)}';
    if (key != _streamKey) {
      _streamKey = key;
      _stream = ref
          .read(repositoryProvider)
          .watchMeals(hid, dayKey(_monday), dayKey(_monday.add(const Duration(days: 6))));
    }
    return _stream!;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final h = ref.watch(activeHouseholdProvider);
    if (h == null) return const Scaffold();
    final shopping = ref.watch(shoppingListProvider).value ?? const [];
    final today = dayKey(DateTime.now());

    return StreamBuilder<List<Meal>>(
      stream: _meals(h.id),
      builder: (context, snap) {
        final meals = snap.data ?? const <Meal>[];
        final missing = missingForShopping(meals, shopping.where((e) => !e.done).map((e) => e.name));
        final loc = MaterialLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(l.planTitle),
            actions: [
              if (missing.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _toShopping(missing),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l.planToShopping(missing.length)),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _week--)),
                  Text(
                    '${loc.formatShortMonthDay(_monday)} – ${loc.formatShortMonthDay(_monday.add(const Duration(days: 6)))}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _week++)),
                ],
              ),
              for (var d = 0; d < 7; d++) _day(context, _monday.add(Duration(days: d)), meals, today),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _suggest,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l.planSuggest),
          ),
        );
      },
    );
  }

  Widget _day(BuildContext context, DateTime day, List<Meal> all, String today) {
    final l = context.l;
    final theme = Theme.of(context);
    final key = dayKey(day);
    final meals = all.where((m) => m.date == key).toList()..sort((a, b) => a.slot.index.compareTo(b.slot.index));
    final weekday = MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$weekday ${day.day}. ${day.month}.',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: key == today ? theme.colorScheme.primary : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (key == today) Text('  · ${l.planToday}', style: theme.textTheme.labelSmall),
              const Spacer(),
              IconButton(
                tooltip: l.planAddMeal,
                onPressed: () => _edit(Meal(id: '', date: key, slot: MealSlot.dinner, title: '')),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          for (final m in meals)
            _MealCard(meal: m, onTap: () => _edit(m), onCooked: () => _cooked(m), onDelete: () => _delete(m)),
          const Divider(),
        ],
      ),
    );
  }

  Future<void> _toShopping(List<String> names) async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final repo = ref.read(repositoryProvider);
    for (final n in names) {
      await repo.addShopping(
        h.id,
        ShoppingEntry(
          id: '',
          name: n,
          categoryId: guessCategory(name: n).id,
          productKey: nameKey(n),
        ),
        user,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.planAddedToShopping(names.length))));
    }
  }

  Future<void> _delete(Meal m) async {
    final h = ref.read(activeHouseholdProvider);
    if (h != null) await ref.read(repositoryProvider).deleteMeal(h.id, m.id);
  }

  /// "Cooked": tick what was used up; those items leave the fridge.
  Future<void> _cooked(Meal m) async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final repo = ref.read(repositoryProvider);
    final active = {for (final i in ref.read(itemsProvider).value ?? const <PantryItem>[]) i.id: i};
    final usable = m.uses.where((u) => active.containsKey(u.itemId)).toList();
    final checked = {for (final u in usable) u.itemId};
    if (usable.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(ctx.l.planWhichUsed),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final u in usable)
                  CheckboxListTile(
                    value: checked.contains(u.itemId),
                    title: Text(u.name),
                    onChanged: (v) => setState(() => v == true ? checked.add(u.itemId) : checked.remove(u.itemId)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l.planCooked)),
            ],
          ),
        ),
      );
      if (ok != true) return;
      for (final id in checked) {
        await repo.finishItem(h.id, active[id]!, ItemStatus.consumed, user);
      }
      if (checked.isNotEmpty) await restock(repo, h.id, user);
    }
    await repo.saveMeal(h.id, m.copyWith(cooked: true), user);
  }

  Future<void> _edit(Meal meal) async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final items = sortByUrgency(ref.read(itemsProvider).value ?? const [], DateTime.now());
    final result = await showModalBottomSheet<Meal>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MealEditor(meal: meal, items: items),
    );
    if (result != null && result.title.trim().isNotEmpty) {
      await ref.read(repositoryProvider).saveMeal(h.id, result, user);
    }
  }

  Future<void> _suggest() async {
    final h = ref.read(activeHouseholdProvider);
    final user = ref.read(userProvider).value;
    if (h == null || user == null) return;
    final items = sortByUrgency(ref.read(itemsProvider).value ?? const [], DateTime.now());
    final plan = await showModalBottomSheet<List<PlannedMeal>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SuggestSheet(items: items),
    );
    if (plan == null || plan.isEmpty) return;
    final today = dateOnly(DateTime.now());
    for (final p in plan) {
      await ref
          .read(repositoryProvider)
          .saveMeal(
            h.id,
            Meal(
              id: '',
              date: dayKey(today.add(Duration(days: p.day))),
              slot: MealSlot.values.firstWhere((s) => s.name == p.slot),
              title: p.title,
              uses: [
                for (final u in p.uses)
                  if (matchItem(u, items) case final i?) MealUse(itemId: i.id, name: i.name),
              ],
              missing: p.missing,
            ),
            user,
          );
    }
    setState(() => _week = 0);
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.onTap, required this.onCooked, required this.onDelete});

  final Meal meal;
  final VoidCallback onTap;
  final VoidCallback onCooked;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        onTap: onTap,
        leading: Text(_slotEmoji[meal.slot]!, style: const TextStyle(fontSize: 24)),
        title: Text(meal.title, style: meal.cooked ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Text(
          [
            slotLabel(context, meal.slot),
            if (meal.uses.isNotEmpty) '🧊 ${meal.uses.map((u) => u.name).join(', ')}',
            if (meal.missing.isNotEmpty) '🛒 ${meal.missing.join(', ')}',
          ].join('\n'),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: meal.uses.isNotEmpty || meal.missing.isNotEmpty,
        trailing: meal.cooked
            ? const Text('✅')
            : PopupMenuButton<String>(
                onSelected: (v) => v == 'cooked' ? onCooked() : (v == 'edit' ? onTap() : onDelete()),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'cooked', child: Text('✅ ${l.planCooked}')),
                  PopupMenuItem(value: 'edit', child: Text(l.planEdit)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
      ),
    );
  }
}

class _MealEditor extends StatefulWidget {
  const _MealEditor({required this.meal, required this.items});

  final Meal meal;
  final List<PantryItem> items;

  @override
  State<_MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends State<_MealEditor> {
  late final _title = TextEditingController(text: widget.meal.title);
  late final _missing = TextEditingController(text: widget.meal.missing.join(', '));
  late final _notes = TextEditingController(text: widget.meal.notes);
  late MealSlot _slot = widget.meal.slot;
  late final Set<String> _uses = {for (final u in widget.meal.uses) u.itemId};

  @override
  void dispose() {
    _title.dispose();
    _missing.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: widget.meal.title.isEmpty,
              decoration: InputDecoration(labelText: l.planMealTitle),
            ),
            const SizedBox(height: 12),
            SegmentedButton<MealSlot>(
              segments: [for (final s in MealSlot.values) ButtonSegment(value: s, label: Text(slotLabel(context, s)))],
              selected: {_slot},
              onSelectionChanged: (s) => setState(() => _slot = s.first),
            ),
            const SizedBox(height: 12),
            Text(l.planFromFridge, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in widget.items)
                  FilterChip(
                    avatar: Text(categoryById(i.categoryId).emoji),
                    label: Text(i.name),
                    selected: _uses.contains(i.id),
                    onSelected: (v) => setState(() => v ? _uses.add(i.id) : _uses.remove(i.id)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _missing,
              decoration: InputDecoration(labelText: l.planMissing),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: InputDecoration(labelText: l.planNotes),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                widget.meal.copyWith(
                  title: _title.text.trim(),
                  slot: _slot,
                  uses: [
                    for (final i in widget.items)
                      if (_uses.contains(i.id)) MealUse(itemId: i.id, name: i.name),
                    // Keep links to items that were used up meanwhile.
                    ...widget.meal.uses.where((u) => !widget.items.any((i) => i.id == u.itemId)),
                  ],
                  missing: [
                    for (final x in _missing.text.split(','))
                      if (x.trim().isNotEmpty) x.trim(),
                  ],
                  notes: _notes.text.trim(),
                ),
              ),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}

/// Days + meals + wishes → AI suggestion (preview, then save), or copy the prompt.
class _SuggestSheet extends ConsumerStatefulWidget {
  const _SuggestSheet({required this.items});

  final List<PantryItem> items;

  @override
  ConsumerState<_SuggestSheet> createState() => _SuggestSheetState();
}

class _SuggestSheetState extends ConsumerState<_SuggestSheet> {
  int _days = 5;
  final _slots = <MealSlot>{MealSlot.lunch, MealSlot.dinner};
  final _wishes = TextEditingController();
  bool _busy = false;
  String? _error;
  List<PlannedMeal>? _plan;

  @override
  void dispose() {
    _wishes.dispose();
    super.dispose();
  }

  String _prompt(BuildContext context) => mealPlanPrompt(
    widget.items,
    _days,
    [
      for (final s in MealSlot.values)
        if (_slots.contains(s)) s.name,
    ],
    _wishes.text,
    Localizations.localeOf(context).languageCode,
    DateTime.now(),
  );

  Future<void> _run() async {
    final prompt = _prompt(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await ref.read(aiServiceProvider).run(AiFeature.recipe, mealPlanRequest(prompt));
      setState(() => _plan = parseMealPlan(text, _days).where((p) => _slots.any((s) => s.name == p.slot)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = context.l.aiError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final aiOn = ref.watch(aiServiceProvider).enabledFor(AiFeature.recipe);
    final plan = _plan;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.planSuggestTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (plan == null) ...[
              Text(l.planDays, style: Theme.of(context).textTheme.titleSmall),
              SegmentedButton<int>(
                segments: [
                  for (final d in [3, 5, 7]) ButtonSegment(value: d, label: Text('$d')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 12),
              Text(l.planMeals, style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in MealSlot.values)
                    FilterChip(
                      label: Text('${_slotEmoji[s]} ${slotLabel(context, s)}'),
                      selected: _slots.contains(s),
                      onSelected: (v) => setState(() => v ? _slots.add(s) : _slots.remove(s)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wishes,
                decoration: InputDecoration(labelText: l.recipesWishes),
              ),
              const SizedBox(height: 16),
              if (_busy)
                Center(
                  child: AiThinking(emoji: '🗓️', text: l.planThinking),
                ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (aiOn && !_busy)
                FilledButton.icon(
                  onPressed: _slots.isEmpty ? null : _run,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(l.planSuggest),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _prompt(context)));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                },
                icon: const Icon(Icons.copy),
                label: Text(l.recipesCopy),
              ),
              if (!aiOn) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.aiNoProvider)),
            ] else ...[
              for (final p in plan)
                ListTile(
                  dense: true,
                  leading: Text(_slotEmoji[MealSlot.values.firstWhere((s) => s.name == p.slot)]!),
                  title: Text(p.title),
                  subtitle: Text(
                    [
                      MaterialLocalizations.of(context).formatShortMonthDay(DateTime.now().add(Duration(days: p.day))),
                      if (p.uses.isNotEmpty) '🧊 ${p.uses.join(', ')}',
                      if (p.missing.isNotEmpty) '🛒 ${p.missing.join(', ')}',
                    ].join(' · '),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(context, plan), child: Text(l.planSaveSuggestion)),
              TextButton(onPressed: () => setState(() => _plan = null), child: Text(l.cancel)),
            ],
          ],
        ),
      ),
    );
  }
}
