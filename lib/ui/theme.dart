import 'package:material_ui/material_ui.dart';

import '../domain/freshness.dart';

/// Cold, clean fridge palette: ice blue accents on enamel white
/// (stainless steel in dark mode).
class GlebaColors {
  static const ice = Color(0xFF4AA8D8);
  static const frost = Color(0xFFDDF1FB);

  static Color freshness(Freshness f, Brightness b) => switch (f) {
        Freshness.fresh => b == Brightness.light ? const Color(0xFF2E9D5B) : const Color(0xFF6BD49A),
        Freshness.soon => b == Brightness.light ? const Color(0xFFE08A00) : const Color(0xFFFFB84D),
        Freshness.today => b == Brightness.light ? const Color(0xFFE0461F) : const Color(0xFFFF7A59),
        Freshness.expired => b == Brightness.light ? const Color(0xFFC62828) : const Color(0xFFFF5C5C),
        Freshness.pastBestBefore => b == Brightness.light ? const Color(0xFF8D6E63) : const Color(0xFFBCAAA4),
      };

  /// Fridge enamel / steel.
  static Color body(Brightness b) => b == Brightness.light ? const Color(0xFFF7FAFC) : const Color(0xFF2B3238);
  static Color bodyEdge(Brightness b) => b == Brightness.light ? const Color(0xFFCAD6DF) : const Color(0xFF151A1E);
  static Color interior(Brightness b) => b == Brightness.light ? const Color(0xFFEAF6FD) : const Color(0xFF1B2730);
  static Color interiorLight(Brightness b) => b == Brightness.light ? const Color(0xFFFFFDF2) : const Color(0xFF34424D);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: GlebaColors.ice, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFEFF4F7) : const Color(0xFF12171B),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
  );
}
