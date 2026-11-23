import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'l10n/app_localizations.dart';
import 'ui/notification_scheduler.dart';
import 'ui/screens/add_item_screen.dart';
import 'ui/screens/ai_settings_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/inventory_screen.dart';
import 'ui/screens/plan_screen.dart';
import 'ui/screens/receipt_screen.dart';
import 'ui/screens/recipes_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/households_screen.dart';
import 'ui/screens/notification_settings_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/shopping_screen.dart';
import 'ui/screens/stats_screen.dart';
import 'ui/screens/take_screen.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/theme.dart';

/// Navigator of the whole app, for dialogs and sheets opened from outside a
/// screen (notification actions, widget taps).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever sign-in state changes.
  final refresh = ValueNotifier(0);
  ref.listen(userProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
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
      GoRoute(path: '/sign-in', builder: (_, _) => Narrow(const SignInScreen())),
      GoRoute(
        path: '/add',
        builder: (_, s) => Narrow(
          AddItemScreen(
            mode: AddMode.values.where((m) => m.name == s.uri.queryParameters['mode']).firstOrNull ?? AddMode.manual,
          ),
        ),
      ),
      GoRoute(
        path: '/inventory',
        builder: (_, s) => Narrow(InventoryScreen(filter: s.uri.queryParameters['filter'])),
      ),
      GoRoute(path: '/plan', builder: (_, _) => Narrow(const PlanScreen())),
      GoRoute(path: '/take', builder: (_, _) => Narrow(const TakeScreen())),
      GoRoute(path: '/stats', builder: (_, _) => Narrow(const StatsScreen())),
      GoRoute(path: '/shopping', builder: (_, _) => Narrow(const ShoppingScreen())),
      GoRoute(path: '/receipt', builder: (_, _) => Narrow(const ReceiptScreen())),
      GoRoute(path: '/recipes', builder: (_, _) => Narrow(const RecipesScreen())),
      GoRoute(path: '/settings/ai', builder: (_, _) => Narrow(const AiSettingsScreen())),
      GoRoute(path: '/history', builder: (_, _) => Narrow(const HistoryScreen())),
      GoRoute(path: '/households', builder: (_, _) => Narrow(const HouseholdsScreen())),
      GoRoute(
        path: '/join/:code',
        builder: (_, s) => Narrow(JoinScreen(code: s.pathParameters['code']!)),
      ),
      GoRoute(path: '/settings', builder: (_, _) => Narrow(const SettingsScreen())),
      GoRoute(path: '/settings/notifications', builder: (_, _) => Narrow(const NotificationSettingsScreen())),
    ],
  );
});

/// Screens other than home are centred at a readable width on big screens.
class Narrow extends StatelessWidget {
  const Narrow(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth <= 840
        ? child
        : ColoredBox(
            color: GlebaColors.backdrop(Theme.of(context).brightness),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Material(elevation: 1, child: child),
              ),
            ),
          ),
  );
}

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
        child: Builder(
          builder: (context) {
            navigatorContext = context;
            return child ?? const SizedBox();
          },
        ),
      ),
    );
  }
}
