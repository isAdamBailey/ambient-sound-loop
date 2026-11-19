/// Shared controls for the session screen and the length picker.
library;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A toggle button: primary fill with black text when selected. Exposes its
/// pressed state to assistive technology.
class ChoiceButton extends StatelessWidget {
  const ChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.semanticLabel,
    this.toggle = true,
    this.minHeight = 48,
    this.fontSize = 16,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final String? semanticLabel;

  /// False for a button that changes a value without a pressed state.
  final bool toggle;
  final double minHeight;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size(44, minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        backgroundColor: selected ? SessionColors.primary : SessionColors.background,
        foregroundColor: selected ? SessionColors.background : SessionColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? SessionColors.primary : SessionColors.border),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Semantics(
          label: semanticLabel,
          excludeSemantics: semanticLabel != null,
          child: Text(
            label,
            maxLines: 1,
            style: SessionText.weight(
              fontSize,
              500,
              color: selected ? SessionColors.background : SessionColors.primary,
            ),
          ),
        ),
      ),
    );
    if (!toggle) return button;
    return MergeSemantics(child: Semantics(toggled: selected, child: button));
  }
}

/// Lays children out in rows of [columns] equal cells.
class CellGrid extends StatelessWidget {
  const CellGrid({super.key, required this.columns, required this.children, this.gap = 8});

  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// An uppercase block label.
class BlockLabel extends StatelessWidget {
  const BlockLabel(this.text, {super.key, this.size = 13});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(text, style: SessionText.label(size: size));
}

/// A level slider: 0–1, announced as a percentage under [label]. Spec #9 §2:
/// the app maps its position to gain with a dB taper.
class LevelSlider extends StatelessWidget {
  const LevelSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  static String percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: SessionColors.primary,
          inactiveTrackColor: SessionColors.border,
          thumbColor: SessionColors.primary,
          overlayColor: const Color(0x338FB3D9),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          semanticFormatterCallback: percent,
        ),
      ),
    ),
  );
}
