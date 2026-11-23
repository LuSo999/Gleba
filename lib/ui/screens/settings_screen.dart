import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../services/push_service.dart';
import '../labels.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final user = ref.watch(userProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(user.displayName ?? user.email ?? ''),
              subtitle: user.email == null ? null : Text(user.email!),
            ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.language),
            trailing: DropdownButton<String>(
              value: s.locale?.languageCode ?? '',
              onChanged: (v) => n.setLocale(v == null || v.isEmpty ? null : Locale(v)),
              items: [
                DropdownMenuItem(value: '', child: Text(l.systemDefault)),
                const DropdownMenuItem(value: 'cs', child: Text('Čeština')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.animation),
            title: Text(l.animations),
            value: s.animations,
            onChanged: n.setAnimations,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.exposure_neg_1),
            title: Text(l.eatOne),
            value: s.partialConsumption,
            onChanged: n.setPartialConsumption,
          ),
          SwitchListTile(
            secondary: const Text('🌍', style: TextStyle(fontSize: 22)),
            title: Text(l.offShare),
            subtitle: Text(l.offShareText),
            isThreeLine: true,
            value: s.shareToOff ?? false,
            onChanged: n.setShareToOff,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l.notifications),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: Text(l.aiTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ai'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.signOut),
            onTap: () async {
              if (user != null) await PushService.instance.unregister(ref.read(repositoryProvider), user);
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
