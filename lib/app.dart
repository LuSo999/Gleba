import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'ui/notification_scheduler.dart';
import 'ui/screens/add_item_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/households_screen.dart';
import 'ui/screens/notification_settings_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever sign-in state changes.
  final refresh = ValueNotifier(0);
  ref.listen(userProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(userProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.value != null;
      final atSignIn = state.matchedLocation == '/sign-in';
      if (!signedIn && !atSignIn) {
        // Remember where we were going (e.g. an invite link).
        return '/sign-in?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (signedIn && atSignIn) return state.uri.queryParameters['from'] ?? '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/add',
        builder: (_, s) => AddItemScreen(
          mode: AddMode.values.where((m) => m.name == s.uri.queryParameters['mode']).firstOrNull ?? AddMode.manual,
        ),
      ),
      GoRoute(path: '/households', builder: (_, _) => const HouseholdsScreen()),
      GoRoute(path: '/join/:code', builder: (_, s) => JoinScreen(code: s.pathParameters['code']!)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/notifications', builder: (_, _) => const NotificationSettingsScreen()),
    ],
  );
});

class GlebaApp extends ConsumerWidget {
  const GlebaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'Gleba',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => NotificationScheduler(
        child: Builder(builder: (context) {
          navigatorContext = context;
          return child ?? const SizedBox();
        }),
      ),
    );
  }
}
