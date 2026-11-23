import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../domain/models.dart';
import '../labels.dart';

Future<void> showInviteDialog(BuildContext context, WidgetRef ref, Household h) async {
  final user = ref.read(userProvider).value;
  if (user == null) return;
  final invite = await ref.read(repositoryProvider).createInvite(h.id, h.name, user.uid);
  if (!context.mounted) return;
  final l = context.l;
  final link = '$kWebAppUrl/join/${invite.code}';
  final text = l.inviteShareText(h.name, link, invite.code);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.invite),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(invite.code,
              style: Theme.of(ctx).textTheme.displaySmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SelectableText(link, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l.inviteValidUntil(formatDate(ctx, invite.expiresAt)), style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
          },
          icon: const Icon(Icons.copy),
          label: Text(l.copy),
        ),
      ],
    ),
  );
}

Future<void> showCreateHouseholdDialog(BuildContext context, WidgetRef ref) async {
  final l = context.l;
  final controller = TextEditingController(text: l.defaultHouseholdName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.createHousehold),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.householdName),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(l.save)),
      ],
    ),
  );
  final user = ref.read(userProvider).value;
  if (name == null || name.trim().isEmpty || user == null) return;
  final id = await ref.read(repositoryProvider).createHousehold(user.uid, name.trim());
  ref.read(activeHouseholdIdProvider.notifier).select(id);
}

class _JoinByCode extends StatefulWidget {
  const _JoinByCode();

  @override
  State<_JoinByCode> createState() => _JoinByCodeState();
}

class _JoinByCodeState extends State<_JoinByCode> {
  final _code = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: l.inviteCode),
            onSubmitted: (_) => _join(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _join, child: Text(l.join)),
      ],
    );
  }

  void _join() {
    final code = _code.text.trim().toUpperCase();
    if (code.isNotEmpty) context.push('/join/$code');
  }
}

class NoHouseholdScreen extends ConsumerWidget {
  const NoHouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Text('🧊', textAlign: TextAlign.center, style: TextStyle(fontSize: 72)),
              Text(l.noHouseholdTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l.noHouseholdText, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showCreateHouseholdDialog(context, ref),
                icon: const Icon(Icons.add_home),
                label: Text(l.createHousehold),
              ),
              const SizedBox(height: 24),
              Text(l.joinHousehold, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const _JoinByCode(),
            ],
          ),
        ),
      ),
    );
  }
}

class HouseholdsScreen extends ConsumerWidget {
  const HouseholdsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final list = ref.watch(householdsProvider).value ?? const [];
    final active = ref.watch(activeHouseholdProvider);
    final user = ref.watch(userProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.households)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final h in list)
            Card(
              child: ListTile(
                leading: Icon(h.id == active?.id ? Icons.home : Icons.home_outlined),
                title: Text(h.name),
                subtitle: Text('👤 ${h.memberIds.length}'),
                onTap: () {
                  ref.read(activeHouseholdIdProvider.notifier).select(h.id);
                  context.pop();
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'invite') await showInviteDialog(context, ref, h);
                    if (v == 'leave' && user != null) {
                      await ref.read(repositoryProvider).leaveHousehold(h.id, user.uid);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'invite', child: Text(l.invite)),
                    PopupMenuItem(value: 'leave', child: Text(l.leaveHousehold)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showCreateHouseholdDialog(context, ref),
            icon: const Icon(Icons.add_home),
            label: Text(l.createHousehold),
          ),
          const SizedBox(height: 24),
          Text(l.joinHousehold, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _JoinByCode(),
        ],
      ),
    );
  }
}

class JoinScreen extends ConsumerWidget {
  const JoinScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.joinHousehold)),
      body: FutureBuilder(
        future: ref.read(repositoryProvider).getInvite(code),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final invite = snap.data;
          if (invite == null) return Center(child: Text(l.inviteInvalid));
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏠', style: TextStyle(fontSize: 64)),
                Text(invite.householdName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final user = ref.read(userProvider).value!;
                    final id = await ref.read(repositoryProvider).joinHousehold(invite.code, user.uid);
                    ref.read(activeHouseholdIdProvider.notifier).select(id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(l.joinedHousehold(invite.householdName))));
                    context.go('/');
                  },
                  child: Text(l.join),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
