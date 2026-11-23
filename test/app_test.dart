import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/app.dart';
import 'package:gleba/app_state.dart';
import 'package:gleba/data/demo_repository.dart';
import 'package:material_ui/material_ui.dart';

/// The freezer door shimmers forever, so pumpAndSettle would never finish.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('demo: sign in, see fridge, open it, switch to list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('cs')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final auth = DemoAuthService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isDemoProvider.overrideWithValue(true),
        authServiceProvider.overrideWithValue(auth),
        repositoryProvider.overrideWithValue(DemoRepository()),
      ],
      child: const GlebaApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Gleba'), findsOneWidget);

    await auth.signInWithGoogle();
    await settle(tester);
    expect(find.text('Domov'), findsOneWidget);
    expect(find.text('Lednice'), findsWidgets);

    // Open the fridge door.
    await tester.tap(find.text('Lednice').last);
    await settle(tester);
    expect(find.text('Máslo'), findsOneWidget);

    // Switch to the urgency list – expired ham comes first.
    await tester.tap(find.text('Spotřebuj nejdřív'));
    await settle(tester);
    final first = tester.widget<Text>(find.descendant(of: find.byType(ListTile).first, matching: find.byType(Text)).at(1));
    expect(first.data, 'Šunka nejvyšší jakosti');
  });

  testWidgets('notification settings: enable morning digest and add a category exception', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('cs')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final auth = DemoAuthService();
    final repo = DemoRepository();
    await auth.signInWithGoogle();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isDemoProvider.overrideWithValue(true),
        authServiceProvider.overrideWithValue(auth),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: const GlebaApp(),
    ));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);
    await tester.tap(find.text('Upozornění'));
    await settle(tester);

    await tester.tap(find.text('Ranní souhrn'));
    await settle(tester);
    expect(find.text('Čas'), findsOneWidget);

    await tester.tap(find.text('Přidat výjimku pro kategorii'));
    await settle(tester);
    await tester.tap(find.textContaining('Mléko').first);
    await settle(tester);
    final rules = await repo.watchNotificationRules('demo').first;
    expect(rules.single.targetId, anyOf('milk', 'milkUht'));
  });
}
