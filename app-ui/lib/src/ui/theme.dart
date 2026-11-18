/// The session screen's look: true black, muted blues, Inter. Spec #9 §8.
library;


import 'package:material_ui/material_ui.dart';

abstract final class SessionColors {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF8FB3D9); // marks, text, selected fill
  static const secondary = Color(0xFF5E7FA3); // secondary text (5.0:1 on black)
  static const border = Color(0xFF1E2B3A);
  static const surface = Color(0xFF0A0F15); // raised surfaces
  static const sheet = Color(0xFF05080C); // the narrow length sheet
}

abstract final class SessionText {
  static TextStyle weight(double size, int weight, {Color color = SessionColors.primary}) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation.weight(weight.toDouble())],
    color: color,
  );

  /// The clock: weight 200, tabular figures.
  static TextStyle clock(double size, {required bool dimmed}) => weight(
    size,
    200,
    color: dimmed ? SessionColors.secondary : SessionColors.primary,
  ).copyWith(height: 1, letterSpacing: -0.02 * size, fontFeatures: const [FontFeature.tabularFigures()]);

  /// Block labels: uppercase, 12–13 px, tracked.
  static TextStyle label({double size = 13}) =>
      weight(size, 400, color: SessionColors.secondary).copyWith(letterSpacing: 0.06 * size);

  static final body = weight(15, 400, color: SessionColors.secondary);
  static final control = weight(16, 500);
  static final tabular = weight(15, 400).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

ThemeData sessionTheme() {
  const scheme = ColorScheme.dark(
    primary: SessionColors.primary,
    onPrimary: SessionColors.background,
    secondary: SessionColors.secondary,
    onSecondary: SessionColors.background,
    surface: SessionColors.background,
    onSurface: SessionColors.primary,
    outline: SessionColors.border,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: SessionColors.background,
    fontFamily: 'Inter',
    textSelectionTheme: const TextSelectionThemeData(cursorColor: SessionColors.primary),
    focusColor: const Color(0x338FB3D9),
  );
}
