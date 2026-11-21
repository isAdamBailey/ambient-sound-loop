/// The session screen: the whole app. Spec #9 §2, §3 and §8.
///
/// The dial carries the clock and the length; under it the preset stops,
/// then one ruled row per layer and the Mono row, then Play. Narrow and portrait
/// screens stack them; landscape screens 900 px and wider put the dial left of
/// the layers. Large screens grow the dial rather than leave it small in a
/// field of black.
library;

import 'dart:math' as math;

import 'package:humspan_native/humspan_native.dart';
import 'package:material_ui/material_ui.dart';

import '../session/length.dart';
import '../session/session_controller.dart';
import '../session/settings.dart';
import 'controls.dart';
import 'length_picker.dart';
import 'privacy.dart';
import 'session_dial.dart';
import 'theme.dart';

/// Landscape windows or screens this wide and up put the dial beside the layers.
const wideBreakpoint = 900.0;

/// The stacked layout never runs wider than this, so a portrait tablet keeps
/// the phone's proportions instead of stretching every row.
const stackedMaxWidth = 600.0;

/// Whether [size] gets the side-by-side layout. A portrait tablet is wider than
/// [wideBreakpoint] but stacks, because its height is where the room is.
bool isWideLayout(Size size) => size.width >= wideBreakpoint && size.width >= size.height;

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.controller, this.onPrivacy = openPrivacyPolicy});

  final SessionController controller;

  /// Opens the privacy policy; tests replace it.
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(MediaQuery.sizeOf(context));
    return Scaffold(
      backgroundColor: SessionColors.ground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              wide ? _WideLayout(controller, onPrivacy) : _NarrowLayout(controller, onPrivacy),
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
  const _NarrowLayout(this.c, this.onPrivacy);
  final SessionController c;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.fromLTRB(20, 12, 20, 20);
    // Everything but the dial takes about this much height.
    const rows = 636.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, stackedMaxWidth + pad.horizontal) - pad.horizontal;
        final height = constraints.maxHeight - pad.vertical;
        // The dial takes what the rows leave, so a phone fits without scrolling
        // and a tablet's spare height goes into a larger dial.
        final dial = math.max(0.0, math.min((height - rows).clamp(176.0, 400.0), width));
        // On a tall screen the column keeps its natural height and is centred,
        // rather than pushing Play to the bottom edge.
        final columnHeight = math.min(height, dial + rows + 48);
        return Center(
          child: SingleChildScrollView(
            padding: pad,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: columnHeight, maxWidth: width),
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
                    _MonoRow(c),
                    const Expanded(child: SizedBox(height: 16)),
                    _PlayRow(c, onPrivacy),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout(this.c, this.onPrivacy);
  final SessionController c;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    // A taller window (a landscape tablet) gets a larger dial; a laptop-sized
    // one keeps 300.
    final dial = (MediaQuery.sizeOf(context).height * 0.42).clamp(300.0, 420.0);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 940 + (dial - 300) * 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: dial + 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SessionDial(controller: c, size: dial, onExact: () => _openExact(context, c, wide: true)),
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
                  children: [..._layers(c), _MonoRow(c), const SizedBox(height: 28), _PlayRow(c, onPrivacy)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      // In mono both ears hear every strike, so there is no left or right.
      heading: s.mono
          ? const Text('BOOM')
          : Semantics(
              label: 'Boom, alternates left and right',
              excludeSemantics: true,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('BOOM'), SizedBox(width: 10), _LeftRight()],
              ),
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

/// Mono under the layers: a listening option, not a layer, so its name is
/// plain words rather than an uppercase heading.
class _MonoRow extends StatelessWidget {
  const _MonoRow(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final on = c.settings.mono;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SessionColors.rule)),
      ),
      child: Row(
        children: [
          // The switch's label says all of this, so it is announced once.
          Expanded(
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Text('Mono', style: SessionText.weight(16, 500, color: on ? SessionColors.ink : SessionColors.dim)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Same sound in both ears',
                      style: SessionText.weight(14, 400, color: SessionColors.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          LayerSwitch(label: 'Mono, same sound in both ears', on: on, onChanged: c.setMono),
        ],
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

/// Play/Stop, the screen's one solid shape, with a line saying what plays,
/// and a faded Privacy link at the end of the row.
class _PlayRow extends StatelessWidget {
  const _PlayRow(this.c, this.onPrivacy);
  final SessionController c;
  final VoidCallback onPrivacy;

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
        TextButton(
          onPressed: onPrivacy,
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 44),
            foregroundColor: SessionColors.dim,
            overlayColor: SessionColors.seaDeep,
          ),
          child: Semantics(
            link: true,
            child: Text(
              'Privacy',
              style: SessionText.weight(
                14,
                400,
                color: SessionColors.dim,
              ).copyWith(decoration: TextDecoration.underline, decorationColor: SessionColors.dim),
            ),
          ),
        ),
      ],
    );
  }
}
