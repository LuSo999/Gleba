import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../services/health_service.dart';
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
            secondary: const Icon(Icons.groups_outlined),
            title: Text(l.askWhoAte),
            subtitle: Text(l.askWhoAteText),
            value: s.askWhoAte,
            onChanged: n.setAskWhoAte,
          ),
          SwitchListTile(
            secondary: const Text('🌍', style: TextStyle(fontSize: 22)),
            title: Text(l.offShare),
            subtitle: Text(l.offShareText),
            isThreeLine: true,
            value: s.shareToOff ?? false,
            onChanged: n.setShareToOff,
          ),
          if (HealthService.supported)
            SwitchListTile(
              secondary: const Text('💚', style: TextStyle(fontSize: 22)),
              title: Text(l.healthWrite),
              subtitle: Text(l.healthWriteText),
              isThreeLine: true,
              value: s.healthWrite,
              onChanged: (v) async {
                if (!v) return n.setHealthWrite(false);
                final messenger = ScaffoldMessenger.of(context);
                final health = HealthService.instance;
                switch (await health.availability()) {
                  case HealthAvailability.unavailable:
                    messenger.showSnackBar(SnackBar(content: Text(l.healthUnavailable)));
                  case HealthAvailability.needsInstall:
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l.healthInstall),
                        action: SnackBarAction(label: 'Play', onPressed: health.install),
                      ),
                    );
                  case HealthAvailability.available:
                    if (await health.enable()) {
                      n.setHealthWrite(true);
                    } else {
                      messenger.showSnackBar(SnackBar(content: Text(l.healthDenied)));
                    }
                }
              },
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
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.privacyPolicy),
            subtitle: const Text('gleba-e9a60.web.app/privacy.html'),
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
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(l.deleteAccount, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.warning_amber),
                  title: Text(l.deleteAccount),
                  content: Text(l.deleteAccountText),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.deleteAccountConfirm),
                    ),
                  ],
                ),
              );
              if (ok != true || user == null || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await PushService.instance.unregister(ref.read(repositoryProvider), user);
                if (!ref.read(isDemoProvider)) {
                  await FirebaseFunctions.instanceFor(region: 'europe-west3').httpsCallable('deleteAccount').call();
                }
                await ref.read(authServiceProvider).signOut();
                messenger.showSnackBar(SnackBar(content: Text(l.deleteAccountDone)));
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
        ],
      ),
    );
  }
}
