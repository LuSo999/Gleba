import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
import 'widgets/item_sheet.dart';

/// Keeps the phone's scheduled notifications in sync with the data and
/// handles taps on notification buttons (eaten / thrown away / snooze).
class NotificationScheduler extends ConsumerStatefulWidget {
  const NotificationScheduler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationScheduler> createState() => _NotificationSchedulerState();
}

class _NotificationSchedulerState extends ConsumerState<NotificationScheduler> {
  Timer? _debounce;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!NotificationService.supported) return;
    NotificationService.instance.init(_handle).then((launchAction) {
      _ready = true;
      _schedule();
      if (launchAction != null) _handle(launchAction);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  AppLocalizations get _l => lookupAppLocalizations(
      ref.read(settingsProvider).locale ?? WidgetsBinding.instance.platformDispatcher.locale);

  void _schedule() {
    if (!_ready) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      final items = ref.read(allItemsProvider).value;
      final rules = ref.read(notificationRulesProvider).value;
      final prefs = ref.read(notificationPrefsProvider).value;
      if (items == null || rules == null || prefs == null) return;
      NotificationService.instance.reschedule(items: items, rules: rules, prefs: prefs, l: _l);
    });
  }

  Future<void> _handle(NotificationAction a) async {
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
        final ctx = navigatorContext;
        if (ctx != null && ctx.mounted) {
          ref.read(activeHouseholdIdProvider.notifier).select(hid);
          await finishWithFanfare(ctx, ref, item, how);
        } else {
          await repo.finishItem(hid, item, how, user);
        }
      case 'snooze':
        await NotificationService.instance.snooze(item, _l);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (NotificationService.supported) {
      ref.listen(allItemsProvider, (_, _) => _schedule());
      ref.listen(notificationRulesProvider, (_, _) => _schedule());
      ref.listen(notificationPrefsProvider, (_, _) => _schedule());
      ref.listen(settingsProvider, (_, _) => _schedule());
    }
    return widget.child;
  }
}

/// Set by the app so notification actions can show the fanfare animation.
BuildContext? navigatorContext;
