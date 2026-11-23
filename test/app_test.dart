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
    await tester.tap(find.byTooltip('Další'));
    await settle(tester);
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.tap(find.text('Upozornění'));
    await settle(tester);

    await tester.tap(find.text('Ranní souhrn'));
    await settle(tester);
    expect(find.text('Čas'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Přidat výjimku pro kategorii'), 200);
    await tester.tap(find.text('Přidat výjimku pro kategorii'));
    await settle(tester);
    await tester.tap(find.textContaining('Mléko').first);
    await settle(tester);
    final rules = await repo.watchNotificationRules('demo').first;
    expect(rules.single.targetId, anyOf('milk', 'milkUht'));
  });

  testWidgets('used up butter can be undone and shows in history', (tester) async {
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
    await tester.tap(find.text('Spotřebuj nejdřív'));
    await settle(tester);
    // Tap the left part of the row – the floating "Add" button covers the right.
    Future<void> openButter() async {
      final tile = find.ancestor(of: find.text('Máslo'), matching: find.byType(ListTile));
      await tester.ensureVisible(tile);
      await settle(tester);
      await tester.tapAt(tester.getTopLeft(tile) + const Offset(30, 20));
      await settle(tester);
    }

    await openButter();

    // Butter is used gradually → "Došlo" instead of "Snězeno".
    expect(find.text('Došlo'), findsOneWidget);
    await tester.tap(find.text('Došlo'));
    await settle(tester);
    expect(find.text('Snězeno: Máslo'), findsOneWidget);
    expect(find.text('Máslo'), findsNothing);

    await tester.tap(find.text('Zpět'));
    await settle(tester);
    expect(find.text('Máslo'), findsOneWidget);
    expect(await repo.watchHistory('home').first, isEmpty); // undo removed the event

    // Eat it for real and put it back from the history.
    await openButter();
    await tester.tap(find.text('Došlo'));
    await settle(tester);
    await tester.tap(find.byTooltip('Další'));
    await settle(tester);
    await tester.tap(find.text('Historie'));
    await settle(tester);
    expect(find.text('Máslo'), findsOneWidget);
    await tester.tap(find.text('Vrátit'));
    await settle(tester);
    final items = await repo.watchActiveItems('home').first;
    expect(items.any((i) => i.name == 'Máslo'), isTrue);
  });

  testWidgets('stock rule refills the shopping list when butter runs out', (tester) async {
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
    await tester.tap(find.text('Spotřebuj nejdřív'));
    await settle(tester);

    Future<void> openButter() async {
      final tile = find.ancestor(of: find.text('Máslo'), matching: find.byType(ListTile));
      await tester.ensureVisible(tile);
      await settle(tester);
      await tester.tapAt(tester.getTopLeft(tile) + const Offset(30, 20));
      await settle(tester);
    }

    // Keep at least 1 butter.
    await openButter();
    await tester.tap(find.text('Hlídat zásobu'));
    await settle(tester);
    await tester.tap(find.text('Uložit'));
    await settle(tester);
    expect(await repo.watchShoppingList('home').first, isEmpty); // still have one

    // Use it up → automatically on the shopping list.
    await openButter();
    await tester.tap(find.text('Došlo'));
    await settle(tester);
    final list = await repo.watchShoppingList('home').first;
    expect(list.single.name, 'Máslo');
    expect(list.single.auto, isTrue);

    await tester.tap(find.byTooltip('Nákupní seznam'));
    await settle(tester);
    expect(find.text('Máslo · 1 ks'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Hlídané zásoby'), 200, scrollable: find.ancestor(of: find.text('Máslo · 1 ks'), matching: find.byType(Scrollable)).first);
    expect(find.textContaining('Hlídané zásoby'), findsOneWidget);
  });
}
