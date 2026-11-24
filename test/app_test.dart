import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/history.dart';
import 'package:gleba/app.dart';
import 'package:gleba/app_state.dart';
import 'package:gleba/data/demo_repository.dart';
import 'package:gleba/data/repository.dart';
import 'package:gleba/domain/meal_plan.dart';
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
    await tester.ensureVisible(find.text('Přidat výjimku pro kategorii'));
    await settle(tester);
    await tester.tap(find.text('Přidat výjimku pro kategorii'));
    await settle(tester);
    await tester.tap(find.textContaining('Mléko').first);
    await settle(tester);
    final rules = await repo.watchNotificationRules('demo').first;
    expect(rules.single.targetId, anyOf('milk', 'milkUht'));
  });

  testWidgets('an item added by mistake can be deleted and undone', (tester) async {
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
    await tester.scrollUntilVisible(find.text('Máslo'), 200, scrollable: find.byType(Scrollable).first);
    final tile = find.ancestor(of: find.text('Máslo'), matching: find.byType(ListTile));
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(30, 20));
    await settle(tester);

    await tester.tap(find.byTooltip('Smazat (přidáno omylem)'));
    await settle(tester);
    expect(find.text('Smazáno: Máslo'), findsOneWidget);
    expect(find.text('Máslo'), findsNothing);
    final events = await repo.fetchEvents('home');
    expect(events.first.type, HistoryType.deleted);
    expect(events.first.isRemoval, isFalse); // not in the statistics

    await tester.tap(find.text('Zpět'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Máslo'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Máslo'), findsOneWidget);
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
      await tester.scrollUntilVisible(find.text('Máslo'), 200, scrollable: find.byType(Scrollable).first);
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
      await tester.scrollUntilVisible(find.text('Máslo'), 200, scrollable: find.byType(Scrollable).first);
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

  testWidgets('statistics screen shows KPIs, chart and tips from history', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('cs')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final auth = DemoAuthService();
    await auth.signInWithGoogle();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isDemoProvider.overrideWithValue(true),
        authServiceProvider.overrideWithValue(auth),
        repositoryProvider.overrideWithValue(DemoRepository()),
      ],
      child: const GlebaApp(),
    ));
    await settle(tester);
    await tester.tap(find.byTooltip('Další'));
    await settle(tester);
    await tester.tap(find.text('Statistiky'));
    await settle(tester);
    expect(find.text('Snězeno včas'), findsOneWidget);
    expect(find.textContaining('Snědeno a vyhozeno'), findsOneWidget);
    await tester.tap(find.text('3 měsíce'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Co se nejvíc vyhazuje'), 200,
        scrollable: find.ancestor(of: find.text('Snězeno včas'), matching: find.byType(Scrollable)).first);
    expect(find.text('Co se nejvíc vyhazuje'), findsOneWidget);
  });

  testWidgets('inventory: swipe right keeps, button eats, undo restores', (tester) async {
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
    // The demo kečup is 3 days past its date → no banner yet (needs > 3).
    await tester.tap(find.byTooltip('Další'));
    await settle(tester);
    await tester.tap(find.text('Inventura'));
    await settle(tester);
    expect(find.text('1 z 13'), findsOneWidget);

    // First card = most urgent: the expired ham. Swipe right = still there.
    expect(find.text('Šunka nejvyšší jakosti'), findsOneWidget);
    await tester.drag(find.text('Šunka nejvyšší jakosti'), const Offset(300, 0));
    await settle(tester);
    expect(find.text('2 z 13'), findsOneWidget);
    final ham = (await repo.watchActiveItems('home').first).firstWhere((i) => i.name.startsWith('Šunka'));
    expect(ham.checkedAt, isNotNull);

    // Eat the next one with the button, then undo.
    await tester.tap(find.text('Snězeno').last);
    await settle(tester);
    expect(find.text('3 z 13'), findsOneWidget);
    expect((await repo.watchActiveItems('home').first).length, 12);
    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);
    expect(find.text('2 z 13'), findsOneWidget);
    expect((await repo.watchActiveItems('home').first).length, 13);

    // Delete (added by mistake): gone, not eaten or thrown, undoable.
    await tester.tap(find.byTooltip('Smazat (přidáno omylem)'));
    await settle(tester);
    expect(find.text('3 z 13'), findsOneWidget);
    expect((await repo.watchActiveItems('home').first).length, 12);
    expect((await repo.fetchEvents('home')).first.type, HistoryType.deleted);
    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);
    expect((await repo.watchActiveItems('home').first).length, 13);
  });

  testWidgets('take screen: search and take one yogurt', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('cs')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final auth = DemoAuthService();
    final repo = DemoRepository();
    await auth.signInWithGoogle();
    final container = ProviderContainer(overrides: [
      isDemoProvider.overrideWithValue(true),
      authServiceProvider.overrideWithValue(auth),
      repositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const GlebaApp()));
    await settle(tester);
    container.read(routerProvider).push('/take');
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'jogurt');
    await settle(tester);
    expect(find.text('Bílý jogurt'), findsOneWidget);
    await tester.tap(find.text('−1'));
    await settle(tester);
    final yogurt = (await repo.watchActiveItems('home').first).firstWhere((i) => i.name == 'Bílý jogurt');
    expect(yogurt.quantity, 2);
    expect(find.text('Snězeno: Bílý jogurt (1 ks)'), findsOneWidget);
  });

  testWidgets('meal plan: add a meal, missing to shopping, cooked uses up the fridge item', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('cs')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final auth = DemoAuthService();
    final repo = DemoRepository();
    await auth.signInWithGoogle();
    final container = ProviderContainer(overrides: [
      isDemoProvider.overrideWithValue(true),
      authServiceProvider.overrideWithValue(auth),
      repositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const GlebaApp()));
    await settle(tester);
    container.read(routerProvider).push('/plan');
    await settle(tester);

    // Today's day header is first in this week's list only if today is Monday, so add via the code path:
    final today = DateTime.now();
    final todayKey = today.toIso8601String().substring(0, 10);
    final chicken = (await repo.watchActiveItems('home').first).firstWhere((i) => i.name == 'Kuřecí prsa');
    await repo.saveMeal(
        'home',
        Meal(id: '', date: todayKey, slot: MealSlot.dinner, title: 'Kuře na paprice',
            uses: [MealUse(itemId: chicken.id, name: chicken.name)], missing: const ['Smetana', 'Paprika']),
        const GlebaUser(uid: 'demo', displayName: 'Demo'));
    await settle(tester);
    expect(find.text('Kuře na paprice'), findsOneWidget);

    await tester.tap(find.text('Chybějící na nákup (2)'));
    await settle(tester);
    expect((await repo.watchShoppingList('home').first).map((e) => e.name), containsAll(['Smetana', 'Paprika']));
    expect(find.textContaining('Chybějící na nákup'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('✅ Uvařeno'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Uvařeno'));
    await settle(tester);
    final items = await repo.watchActiveItems('home').first;
    expect(items.any((i) => i.id == chicken.id), isFalse);
    expect(find.text('✅'), findsOneWidget);
  });
}
