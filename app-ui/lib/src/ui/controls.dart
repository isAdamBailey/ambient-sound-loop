/// The session screen's controls. Each kind of job has its own form: a
/// switch turns a layer on, an underlined word picks one of a few, a stepper
/// moves through a range, a slider sets a level.
library;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Every touch target is at least this tall and wide.
const kTarget = 44.0;

/// A layer's on/off switch: a 46 x 28 track inside a 48 x 44 target. Exposes
/// its toggled state under [label].
class LayerSwitch extends StatelessWidget {
  const LayerSwitch({super.key, required this.label, required this.on, required this.onChanged});

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: on,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      onTap: () => onChanged(!on),
      radius: 28,
      child: SizedBox(
        width: 56,
        height: kTarget,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 28,
            padding: const EdgeInsets.all(4),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? SessionColors.ink : SessionColors.ground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? SessionColors.ink : SessionColors.dim, width: 1.5),
            ),
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? SessionColors.ground : SessionColors.dim,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One option in a row of choices: a 44 px target, its label, and a 2 px
/// underline when chosen. A null [onTap] disables it.
class UnderlinedOption extends StatelessWidget {
  const UnderlinedOption({
    super.key,
    required this.child,
    required this.chosen,
    required this.color,
    required this.onTap,
    this.semanticLabel,
    this.underlineWidth = 28,
  });

  final Widget child;
  final bool chosen;
  final Color color;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double underlineWidth;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: chosen,
    enabled: onTap != null,
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: kTarget, minHeight: kTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 4),
              SizedBox(height: 20, child: Center(child: child)),
              const SizedBox(height: 4),
              Container(height: 2, width: underlineWidth, color: chosen ? color : Colors.transparent),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One of a few: words in a row, the chosen one in ink and underlined.
/// [muted] draws every word in the secondary tone (its layer is off) while
/// leaving the choice usable.
class WordChoice<T> extends StatelessWidget {
  const WordChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.muted = false,
    this.figures = false,
    this.semanticLabel,
    this.gap = 20,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool muted;
  final bool figures;
  final String Function(T value)? semanticLabel;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final MapEntry(:key, :value) in options.entries) {
      if (children.isNotEmpty) children.add(SizedBox(width: gap - 8));
      final chosen = key == selected;
      final color = chosen && !muted ? SessionColors.ink : SessionColors.dim;
      children.add(UnderlinedOption(
        chosen: chosen,
        color: color,
        onTap: () => onSelected(key),
        semanticLabel: semanticLabel?.call(key),
        child: Text(
          value,
          maxLines: 1,
          style: figures ? SessionText.figures(16, color: color) : SessionText.weight(16, 400, color: color),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// A value in a range, moved one step at a time with − and +. The ends of the
/// range disable their button.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.text,
    required this.semanticValue,
    required this.onLower,
    required this.onRaise,
    required this.lowerLabel,
    required this.raiseLabel,
    this.muted = false,
  });

  final String text;
  final String semanticValue;
  final VoidCallback? onLower;
  final VoidCallback? onRaise;
  final String lowerLabel;
  final String raiseLabel;
  final bool muted;

  Widget _button(IconData icon, String label, VoidCallback? onPressed) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      onTap: onPressed,
      radius: 24,
      child: SizedBox.square(
        dimension: kTarget,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Faded ink (5.4:1) when usable; the hairline once the end of
              // the range disables it.
              border: Border.all(color: onPressed == null ? SessionColors.rule : SessionColors.dim, width: 1.5),
            ),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null || muted ? SessionColors.dim : SessionColors.ink,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _button(Icons.remove_rounded, lowerLabel, onLower),
      SizedBox(
        width: 68,
        child: Semantics(
          label: semanticValue,
          excludeSemantics: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: SessionText.figures(17, color: muted ? SessionColors.dim : SessionColors.ink),
          ),
        ),
      ),
      _button(Icons.add_rounded, raiseLabel, onRaise),
    ],
  );
}

/// A level slider: 0–1, announced as a percentage under [label], with the
/// percentage written at its end. Spec #9 §2: the app maps its position to
/// gain with a dB taper.
class LevelSlider extends StatelessWidget {
  const LevelSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.muted = false,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool muted;

  static String percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: MergeSemantics(
            child: Semantics(
              label: label,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: muted ? SessionColors.dim : SessionColors.sea,
                  inactiveTrackColor: SessionColors.rule,
                  thumbColor: muted ? SessionColors.dim : SessionColors.ink,
                  overlayColor: SessionColors.seaWash,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 0, pressedElevation: 0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                  trackShape: const RectangularSliderTrackShape(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: SizedBox(
                  height: kTarget,
                  child: Slider(
                    value: v,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                    semanticFormatterCallback: percent,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: ExcludeSemantics(
            child: Text(
              percent(v),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: SessionText.figures(13, color: SessionColors.dim).copyWith(letterSpacing: -0.5),
            ),
          ),
        ),
      ],
    );
  }
}
