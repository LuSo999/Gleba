import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../data/firebase_repository.dart';
import '../data/repository.dart';
import '../domain/models.dart';
import '../firebase_options.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/item_sheet.dart' show restock;
import 'widget_service.dart';

/// Runs in a background isolate when a widget button is tapped
/// ("gleba://take?h=…&i=…" or "gleba://undo"), without opening the app.
@pragma('vm:entry-point')
Future<void> widgetInteraction(Uri? uri) async {
  if (uri == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = FirebaseAuth.instance;
  final u = auth.currentUser ?? await auth.authStateChanges().first;
  if (u == null) return;
  final user = GlebaUser(uid: u.uid, email: u.email, displayName: u.displayName);
  final repo = FirestoreRepository(FirebaseFirestore.instance);
  final lang = await HomeWidget.getWidgetData<String>('lang') ?? 'cs';
  final l = lookupAppLocalizations(Locale(lang == 'en' ? 'en' : 'cs'));

  switch (uri.host) {
    case 'take':
      final hid = uri.queryParameters['h'], id = uri.queryParameters['i'];
      if (hid == null || id == null) break;
      final item = await repo.getItem(hid, id);
      if (item == null || item.status != ItemStatus.active) break;
      final one = item.unit == 'ks' && item.quantity > 1;
      final eventId = await repo.finishItem(hid, item, ItemStatus.consumed, user, quantity: one ? 1 : null);
      await restock(repo, hid, user);
      await HomeWidget.saveWidgetData<String>('lastText', l.widgetTaken(one ? '${item.name} (1 ks)' : item.name));
      await HomeWidget.saveWidgetData<String>(
          'last', jsonEncode({'h': hid, 'i': id, 'e': eventId, 'q': item.quantity}));
      await HomeWidget.saveWidgetData<String>('lastAt', '${DateTime.now().millisecondsSinceEpoch}');
    case 'undo':
      final raw = await HomeWidget.getWidgetData<String>('last');
      if (raw == null) break;
      final last = jsonDecode(raw) as Map<String, dynamic>;
      await repo.undoFinish(
        last['h'] as String,
        PantryItem(
          id: last['i'] as String,
          name: '',
          categoryId: 'other',
          expiryDate: DateTime.now(),
          quantity: (last['q'] as num).toDouble(),
        ),
        last['e'] as String,
      );
      await HomeWidget.saveWidgetData<String>('last', null);
      await HomeWidget.saveWidgetData<String>('lastAt', '0');
  }

  // Redraw with fresh data from all the user's households.
  final households = await repo.watchHouseholds(user.uid).first;
  final items = <PantryItem>[
    for (final h in households) ...[for (final i in await repo.watchActiveItems(h.id).first) i.withHousehold(h.id)],
  ];
  await WidgetService.update(items, l);
}
