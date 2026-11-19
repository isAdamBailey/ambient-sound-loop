/// The session screen: the whole app. Spec #9 §2, §3 and §8.
///
/// The dial carries the clock and the length; under it the preset stops,
/// then one ruled row per layer, then Play. Narrow screens stack them; at
/// 900 px and up the dial sits left of the layers.
library;

import 'dart:math' as math;

import 'package:humspan_native/humspan_native.dart';
import 'package:material_ui/material_ui.dart';

import '../session/length.dart';
import '../session/session_controller.dart';
import '../session/settings.dart';
import 'controls.dart';
import 'length_picker.dart';
import 'session_dial.dart';
import 'theme.dart';

/// Windows or screens this wide and up put the dial beside the layers.
const wideBreakpoint = 900.0;

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    return Scaffold(
      backgroundColor: SessionColors.ground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => wide ? _WideLayout(controller) : _NarrowLayout(controller),
        ),
      ),
    );
  }
}

Future<void> _openExact(BuildContext context, SessionController c, {required bool wide}) async {
  final chosen = await showExactLength(context, current: c.settings.length, wide: wide);
  if (chosen != null) c.setLength(chosen);
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.fromLTRB(20, 12, 20, 20);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The dial takes what the rows leave, so a phone fits without scrolling.
        final dial = math.max(
          0.0,
          math.min((constraints.maxHeight - 590).clamp(176.0, 260.0), constraints.maxWidth - pad.horizontal),
        );
        return SingleChildScrollView(
          padding: pad,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - pad.vertical),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SessionDial(controller: c, size: dial, onExact: () => _openExact(context, c, wide: false)),
                  ),
                  const SizedBox(height: 4),
                  _StopsOrStatus(c),
                  const SizedBox(height: 10),
                  ..._layers(c),
                  const Expanded(child: SizedBox(height: 16)),
                  _PlayRow(c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SessionDial(controller: c, size: 300, onExact: () => _openExact(context, c, wide: true)),
                  ),
                  const SizedBox(height: 8),
                  _StopsOrStatus(c),
                ],
              ),
            ),
            const SizedBox(width: 64),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [..._layers(c), const SizedBox(height: 28), _PlayRow(c)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<Widget> _layers(SessionController c) {
  final s = c.settings;
  final beat = beatFrequencies.indexOf(s.beatHz);
  return [
    _LayerRow(
      heading: const Text('NOISE'),
      switchLabel: 'Noise',
      onToggle: c.setNoise,
      controlName: 'Color',
      // The colors stay usable while noise is off, ready for when it returns.
      control: WordChoice<NoiseColor>(
        options: const {NoiseColor.white: 'White', NoiseColor.pink: 'Pink', NoiseColor.brown: 'Brown'},
        selected: s.color,
        muted: !s.noiseOn,
        onSelected: c.setColor,
      ),
      layer: SoundLayer.noise,
      c: c,
    ),
    _LayerRow(
      heading: const Text('BINAURAL BEAT'),
      switchLabel: 'Binaural beat',
      onToggle: c.setBinaural,
      controlName: 'Beat',
      control: ValueStepper(
        text: '${s.beatHz} Hz',
        semanticValue: 'Beat frequency, ${s.beatHz} hertz',
        lowerLabel: 'Lower beat frequency',
        raiseLabel: 'Raise beat frequency',
        muted: !s.binauralOn,
        onLower: beat > 0 ? () => c.setBeatHz(beatFrequencies[beat - 1]) : null,
        onRaise: beat < beatFrequencies.length - 1 ? () => c.setBeatHz(beatFrequencies[beat + 1]) : null,
      ),
      layer: SoundLayer.binaural,
      c: c,
    ),
    _LayerRow(
      heading: Semantics(
        label: 'Boom, alternates left and right',
        excludeSemantics: true,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('BOOM'), SizedBox(width: 10), _LeftRight()]),
      ),
      switchLabel: 'Boom',
      onToggle: c.setBoom,
      controlName: 'Every',
      control: WordChoice<int>(
        options: {for (final g in boomIntervals) g: '$g s'},
        selected: s.boomSeconds,
        muted: !s.boomOn,
        figures: true,
        gap: 16,
        semanticLabel: (g) => 'Boom every $g seconds',
        onSelected: c.setBoomSeconds,
      ),
      layer: SoundLayer.boom,
      c: c,
    ),
  ];
}

/// "left ⇄ right" beside the Boom heading: the strike alternates ears.
class _LeftRight extends StatelessWidget {
  const _LeftRight();

  @override
  Widget build(BuildContext context) {
    final style = SessionText.weight(13, 400, color: SessionColors.dim);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('left', style: style),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.swap_horiz_rounded, size: 16, color: SessionColors.dim),
        ),
        Text('right', style: style),
      ],
    );
  }
}

/// One layer: a hairline rule, the heading and its switch, the layer's own
/// control, and its level. An off layer keeps its height and stays usable;
/// only its tone drops.
class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.heading,
    required this.switchLabel,
    required this.onToggle,
    required this.controlName,
    required this.control,
    required this.layer,
    required this.c,
  });

  final Widget heading;
  final String switchLabel;
  final ValueChanged<bool> onToggle;
  final String controlName;
  final Widget control;
  final SoundLayer layer;
  final SessionController c;

  static const _levelLabels = {
    SoundLayer.noise: 'Noise level',
    SoundLayer.binaural: 'Binaural level',
    SoundLayer.boom: 'Boom level',
  };

  @override
  Widget build(BuildContext context) {
    final on = c.settings.isOn(layer);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SessionColors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DefaultTextStyle(
                    style: SessionText.label(color: on ? SessionColors.ink : SessionColors.dim),
                    child: Semantics(header: true, child: heading),
                  ),
                ),
                LayerSwitch(label: switchLabel, on: on, onChanged: onToggle),
              ],
            ),
            Row(
              children: [
                ExcludeSemantics(
                  child: Text(controlName, style: SessionText.weight(14, 400, color: SessionColors.dim)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: control),
                  ),
                ),
              ],
            ),
            LevelSlider(
              label: _levelLabels[layer]!,
              value: c.settings.level(layer),
              muted: !on,
              onChanged: (v) => c.setLevel(layer, v),
              onChangeEnd: (_) => c.saveLevels(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preset stops under the dial, or, while headphones are out, the
/// paused status in their place. Locked while a session runs.
class _StopsOrStatus extends StatelessWidget {
  const _StopsOrStatus(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    if (c.phase == SessionPhase.paused) return const _PausedStatus();
    final locked = c.lengthLocked;
    // Equal shares of the width, so the six stops never overflow.
    return Row(
      children: [
        for (final p in lengthPresets)
          Expanded(
            child: _Stop(
              preset: p,
              selected: c.settings.length == p.length,
              onTap: locked ? null : () => c.setLength(p.length),
            ),
          ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.preset, required this.selected, required this.onTap});

  final LengthPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected && onTap != null ? SessionColors.ink : SessionColors.dim;
    return UnderlinedOption(
      chosen: selected,
      color: color,
      onTap: onTap,
      semanticLabel: preset.length.tileText,
      underlineWidth: 24,
      child: preset.length is UntilStop
          ? Icon(Icons.all_inclusive_rounded, size: 20, color: color)
          : Text(preset.label, style: SessionText.figures(14, color: color)),
    );
  }
}

class _PausedStatus extends StatelessWidget {
  const _PausedStatus();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: SizedBox(
      height: kTarget,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.headset_off_outlined, size: 18, color: SessionColors.state),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Headphones disconnected. Paused.',
              style: SessionText.weight(14, 500, color: SessionColors.state),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Play/Stop, the screen's one solid shape, with a line saying what plays.
class _PlayRow extends StatelessWidget {
  const _PlayRow(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final playing = c.phase == SessionPhase.playing;
    final enabled = c.canPlay;
    final length = c.settings.length;
    final String note;
    if (!enabled) {
      note = 'Turn on a sound to play.';
    } else if (c.phase == SessionPhase.stopped) {
      note = length is UntilStop
          ? '${c.soundName}\nuntil you stop'
          : '${c.soundName}\nfor ${length.tileText}, then fades out';
    } else {
      note = c.soundName;
    }

    return Row(
      children: [
        SizedBox.square(
          dimension: 68,
          child: IconButton(
            onPressed: enabled ? c.playOrStop : null,
            style: IconButton.styleFrom(
              backgroundColor: playing ? Colors.transparent : SessionColors.ink,
              foregroundColor: playing ? SessionColors.ink : SessionColors.ground,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: SessionColors.dim,
              side: playing
                  ? const BorderSide(color: SessionColors.ink, width: 1.5)
                  : enabled
                  ? null
                  : const BorderSide(color: SessionColors.rule, width: 1.5),
              shape: const CircleBorder(),
            ),
            icon: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: playing ? 30 : 38,
              semanticLabel: playing ? 'Stop' : 'Play',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(note, style: SessionText.note, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
