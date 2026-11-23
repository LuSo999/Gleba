import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../domain/freshness.dart';
import '../domain/models.dart';
import '../domain/shelf_life.dart';
import '../l10n/app_localizations.dart';
import '../ui/labels.dart' show relativeExpiry;
import '../ui/theme.dart';

/// Keeps the Android home-screen widget (GlebaWidgetProvider.kt) up to date.
class WidgetService {
  static const _provider = 'cz.gleba.gleba.GlebaWidgetProvider';
  static const _days = 8;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The widget data: for each item its label and colour for today and the
  /// next 7 days, so the widget can move on by itself without the app.
  static Map<String, String> buildData(List<PantryItem> items, AppLocalizations l, DateTime now) {
    final today = dateOnly(now);
    final top = sortByUrgency(items, now).take(5);
    final list = [
      for (final i in top)
        {
          'n': i.name,
          'e': categoryById(i.categoryId).emoji,
          'r': [for (var d = 0; d < _days; d++) relativeExpiry(l, i.expiryDate, today.add(Duration(days: d)))],
          'c': [
            for (var d = 0; d < _days; d++)
              GlebaColors.freshness(freshnessOf(i, today.add(Duration(days: d))), Brightness.light).toARGB32(),
          ],
        },
    ];
    return {
      'items': jsonEncode(list),
      'base': today.toIso8601String().substring(0, 10),
      'title': l.widgetTitle,
      'empty': l.nothingUrgent,
    };
  }

  static Future<void> update(List<PantryItem> items, AppLocalizations l) async {
    if (!supported) return;
    final now = DateTime.now();
    try {
      for (final e in buildData(items, l, now).entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
      // Redraw just after each of the next midnights ("tomorrow" → "today").
      final today = dateOnly(now);
      await HomeWidget.scheduleWidgetUpdates(
        [for (var d = 1; d <= 7; d++) today.add(Duration(days: d, minutes: 1))],
        qualifiedAndroidName: _provider,
      );
    } catch (e) {
      debugPrint('widget update failed: $e');
    }
  }

  /// Where a tap on the widget should lead: '/add?mode=scan' for "+", else '/'.
  static String routeFor(Uri? uri) => uri?.host == 'add' ? '/add?mode=scan' : '/';
}
