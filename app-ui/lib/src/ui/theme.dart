/// The session screen's look: near-black ground, parchment ink, one sea-blue
/// for measured quantities, amber only for state changes. Atkinson
/// Hyperlegible Next for words, its Mono for figures.
library;

import 'package:material_ui/material_ui.dart';

abstract final class SessionColors {
  static const ground = Color(0xFF05090D); // the screen
  static const ink = Color(0xFFD6CCB2); // text, marks, the Play fill (12:1)
  static const dim = Color(0xFF8C8676); // secondary text, off and locked controls (5.4:1)
  static const rule = Color(0xFF1A232B); // hairlines, slider and dial tracks
  static const sea = Color(0xFF4F7F95); // measured amounts: the length arc, level fills
  static const seaDeep = Color(0xFF1D3A4A); // focus and press washes
  static const seaWash = Color(0x331D3A4A); // seaDeep at 20 %: slider overlay, highlight
  static const state = Color(0xFFE0A85C); // state changes only (Paused)
  static const raised = Color(0xFF0B1117); // the exact-length sheet
}

abstract final class SessionText {
  static const sans = 'Atkinson Hyperlegible Next';
  static const mono = 'Atkinson Hyperlegible Mono';

  static TextStyle weight(double size, int weight, {Color color = SessionColors.ink, String family = sans}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation.weight(weight.toDouble())],
        color: color,
        height: 1.25,
      );

  /// Figures: durations, frequencies, percentages, times.
  static TextStyle figures(double size, {int w = 400, Color color = SessionColors.ink}) =>
      weight(size, w, color: color, family: mono).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// The clock in the dial's center.
  static TextStyle clock(double size, {required bool dimmed}) =>
      figures(size, w: 200, color: dimmed ? SessionColors.dim : SessionColors.ink)
          .copyWith(height: 1, letterSpacing: -0.02 * size);

  /// Layer headings: uppercase, tracked.
  static TextStyle label({double size = 12, Color color = SessionColors.dim}) =>
      weight(size, 500, color: color).copyWith(letterSpacing: 0.08 * size);

  static final body = weight(15, 400, color: SessionColors.dim);
  static final note = weight(14, 400, color: SessionColors.dim).copyWith(height: 1.4);
}

ThemeData sessionTheme() {
  const scheme = ColorScheme.dark(
    primary: SessionColors.ink,
    onPrimary: SessionColors.ground,
    secondary: SessionColors.sea,
    onSecondary: SessionColors.ground,
    surface: SessionColors.ground,
    onSurface: SessionColors.ink,
    outline: SessionColors.rule,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: SessionColors.ground,
    fontFamily: SessionText.sans,
    splashFactory: NoSplash.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SessionColors.ink,
      selectionColor: SessionColors.seaDeep,
      selectionHandleColor: SessionColors.ink,
    ),
    focusColor: SessionColors.seaDeep,
    highlightColor: SessionColors.seaWash,
  );
}
