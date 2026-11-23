import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleba/domain/models.dart';
import 'package:gleba/l10n/app_localizations.dart';
import 'package:gleba/services/widget_service.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('widget data carries labels for the next days, most urgent first', () {
    final now = DateTime(2026, 11, 23, 20);
    final l = lookupAppLocalizations(const Locale('cs'));
    final data = WidgetService.buildData([
      PantryItem(id: 'a', name: 'Máslo', categoryId: 'butter', expiryDate: DateTime(2026, 12, 20)),
      PantryItem(id: 'b', name: 'Mléko', categoryId: 'milk', expiryDate: DateTime(2026, 11, 24)),
    ], l, now);
    expect(data['base'], '2026-11-23');
    expect(data['title'], 'Brzy projde');
    final items = jsonDecode(data['items']!) as List;
    expect(items.first['n'], 'Mléko');
    expect(items.first['e'], '🥛');
    expect((items.first['r'] as List).take(3), ['zítra', 'dnes', 'prošlo včera']);
    expect((items.first['c'] as List).length, 8);
    expect(items.first['i'], 'b');
    expect(items.first['m'], isFalse);
    expect(data['takeLabel'], 'Beru');
    expect(data['lang'], 'cs');
  });

  test('widget taps', () {
    expect(WidgetService.routeFor(Uri.parse('gleba://add')), '/add?mode=scan');
    expect(WidgetService.routeFor(Uri.parse('gleba://open')), '/');
    expect(WidgetService.routeFor(Uri.parse('gleba://take-search')), '/take');
    expect(WidgetService.routeFor(null), '/');
  });
}
