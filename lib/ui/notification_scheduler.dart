import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart' show routerProvider;
import '../app_state.dart';
import '../domain/models.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'widgets/item_sheet.dart';

/// Registers the phone for push notifications after sign-in and handles the
/// notification buttons (eaten / thrown away / remind me tomorrow).
class NotificationScheduler extends ConsumerStatefulWidget {
  const NotificationScheduler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationScheduler> createState() => _NotificationSchedulerState();
}

class _NotificationSchedulerState extends ConsumerState<NotificationScheduler> {
  @override
  void initState() {
    super.initState();
    // Demo mode has no server, so no push notifications.
    if (!NotificationService.supported || ref.read(isDemoProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
    NotificationService.instance.init(_handle).then((launchAction) {
      if (launchAction != null) _handle(launchAction);
    });
  }

  void _register() {
    final user = ref.read(userProvider).value;
    if (user == null || ref.read(isDemoProvider)) return;
    final locale = ref.read(settingsProvider).locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    PushService.instance.register(ref.read(repositoryProvider), user, locale.languageCode);
  }

  Future<void> _handle(NotificationAction a) async {
    if (a.kind == 'inventory') {
      ref.read(routerProvider).push('/inventory');
      return;
    }
    final hid = a.householdId, id = a.itemId;
    if (hid == null || id == null || a.action == 'open') return;
    // The user may not be signed in yet when the app was cold-started.
    final user = ref.read(userProvider).value ?? await ref.read(userProvider.future);
    if (user == null) return;
    final repo = ref.read(repositoryProvider);
    final item = (await repo.getItem(hid, id))?.withHousehold(hid);
    if (item == null || item.status != ItemStatus.active) return;
    switch (a.action) {
      case 'eaten' || 'discarded':
        final how = a.action == 'eaten' ? ItemStatus.consumed : ItemStatus.discarded;
        ref.read(activeHouseholdIdProvider.notifier).select(hid);
        final ctx = navigatorContext;
        if (ctx != null && ctx.mounted) {
          await finishWithFanfare(ctx, ref, item, how);
        } else {
          await repo.finishItem(hid, item, how, user);
        }
      case 'snooze':
        await repo.snoozeItem(user.uid, item, DateTime.now().add(const Duration(days: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (NotificationService.supported && !ref.read(isDemoProvider)) {
      ref.listen(userProvider, (_, _) => _register());
      ref.listen(settingsProvider, (prev, next) {
        if (prev?.locale != next.locale) _register();
      });
    }
    return widget.child;
  }
}

/// Set by the app so notification actions can show the undo snackbar.
BuildContext? navigatorContext;
