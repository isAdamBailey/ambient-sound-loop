/// The session screen: the whole app. Spec #9 §2, §3 and §8.
library;

import 'package:humspan_native/humspan_native.dart';
import 'package:material_ui/material_ui.dart';

import '../session/session_controller.dart';
import '../session/settings.dart';
import 'controls.dart';
import 'length_picker.dart';
import 'theme.dart';

/// Windows or screens this wide and up lay the blocks out in one row.
const wideBreakpoint = 900.0;

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    return Scaffold(
      backgroundColor: SessionColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => wide ? _WideLayout(controller) : _NarrowLayout(controller),
        ),
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.fromLTRB(24, 24, 24, 24);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: pad,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - pad.vertical),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Center(child: _ClockBlock(c, wide: false))),
                const SizedBox(height: 20),
                _NoiseBlock(c, wide: false),
                const SizedBox(height: 18),
                _BinauralBlock(c),
                const SizedBox(height: 18),
                _BoomBlock(c),
                const SizedBox(height: 18),
                _LengthBlock(c, wide: false),
                const SizedBox(height: 24),
                Center(child: _PlayButton(c)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 20);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 5, child: _ClockBlock(c, wide: true)),
            gap,
            Expanded(flex: 5, child: _NoiseBlock(c, wide: true)),
            gap,
            Expanded(flex: 4, child: _BinauralBlock(c)),
            gap,
            Expanded(flex: 4, child: _BoomBlock(c)),
            gap,
            Expanded(flex: 5, child: _LengthBlock(c, wide: true)),
            gap,
            _PlayButton(c),
          ],
        ),
      ),
    );
  }
}

class _ClockBlock extends StatelessWidget {
  const _ClockBlock(this.c, {required this.wide});
  final SessionController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final paused = c.phase == SessionPhase.paused;
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        // Flutter has no timer role; the clock is labelled and never announced
        // as it ticks (no live region).
        Semantics(
          label: 'Clock, ${c.clockCaption}',
          value: c.clockText,
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: wide ? Alignment.centerLeft : Alignment.center,
            child: Text(c.clockText, maxLines: 1, style: SessionText.clock(wide ? 52 : 72, dimmed: paused)),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(child: Text(c.clockCaption, style: SessionText.body)),
        if (paused) ...[
          const SizedBox(height: 12),
          const _PausedPill(),
        ],
      ],
    );
  }
}

class _PausedPill extends StatelessWidget {
  const _PausedPill();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: SessionColors.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.headset_off_outlined, size: 18, color: SessionColors.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Text('Headphones disconnected. Paused.', style: SessionText.weight(14, 400)),
          ),
        ],
      ),
    ),
  );
}

class _NoiseBlock extends StatelessWidget {
  const _NoiseBlock(this.c, {required this.wide});
  final SessionController c;
  final bool wide;

  static const _labels = {NoiseColor.white: 'White', NoiseColor.pink: 'Pink', NoiseColor.brown: 'Brown'};

  @override
  Widget build(BuildContext context) {
    final on = c.settings.noiseOn;
    final toggle = ChoiceButton(
      label: on ? 'On' : 'Off',
      semanticLabel: 'Noise',
      selected: on,
      onPressed: () => c.setNoise(!on),
    );
    // The colors stay usable while noise is off, ready for when it returns.
    final colors = [
      for (final color in NoiseColor.values)
        ChoiceButton(
          label: _labels[color]!,
          selected: c.settings.color == color,
          onPressed: () => c.setColor(color),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BlockLabel('NOISE'),
        const SizedBox(height: 8),
        // Wide blocks are narrow columns: the toggle gets its own row there.
        if (wide) ...[
          CellGrid(columns: 1, children: [toggle]),
          const SizedBox(height: 8),
          CellGrid(columns: 3, children: colors),
        ] else
          CellGrid(columns: 4, children: [toggle, ...colors]),
        _LevelSlider(c, SoundLayer.noise),
      ],
    );
  }
}

/// A layer's level slider, under its buttons. Usable while the layer is off.
class _LevelSlider extends StatelessWidget {
  const _LevelSlider(this.c, this.layer);
  final SessionController c;
  final SoundLayer layer;

  static const _labels = {SoundLayer.noise: 'Noise level', SoundLayer.binaural: 'Binaural level', SoundLayer.boom: 'Boom level'};

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: LevelSlider(
      label: _labels[layer]!,
      value: c.settings.level(layer),
      onChanged: (v) => c.setLevel(layer, v),
      onChangeEnd: (_) => c.saveLevels(),
    ),
  );
}

class _BinauralBlock extends StatelessWidget {
  const _BinauralBlock(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final on = c.settings.binauralOn;
    final hz = c.settings.beatHz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BlockLabel('BINAURAL BEAT'),
        const SizedBox(height: 8),
        CellGrid(
          columns: 2,
          children: [
            ChoiceButton(
              label: on ? 'On' : 'Off',
              semanticLabel: 'Binaural beat',
              selected: on,
              onPressed: () => c.setBinaural(!on),
            ),
            ChoiceButton(
              label: '$hz Hz',
              semanticLabel: 'Beat frequency, $hz hertz. Change.',
              selected: false,
              toggle: false,
              onPressed: c.nextBeat,
            ),
          ],
        ),
        _LevelSlider(c, SoundLayer.binaural),
      ],
    );
  }
}

class _BoomBlock extends StatelessWidget {
  const _BoomBlock(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final on = c.settings.boomOn;
    final seconds = c.settings.boomSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BlockLabel('BOOM'),
        const SizedBox(height: 8),
        CellGrid(
          columns: 2,
          children: [
            ChoiceButton(
              label: on ? 'On' : 'Off',
              semanticLabel: 'Boom',
              selected: on,
              onPressed: () => c.setBoom(!on),
            ),
            ChoiceButton(
              label: '$seconds s',
              semanticLabel: 'Boom rate, $seconds seconds. Change.',
              selected: false,
              toggle: false,
              onPressed: c.nextBoom,
            ),
          ],
        ),
        _LevelSlider(c, SoundLayer.boom),
      ],
    );
  }
}

class _LengthBlock extends StatelessWidget {
  const _LengthBlock(this.c, {required this.wide});
  final SessionController c;
  final bool wide;

  Future<void> _open(BuildContext context) async {
    final chosen = await showLengthPicker(context, current: c.settings.length, wide: wide);
    if (chosen != null) c.setLength(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final value = c.settings.length.tileText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _open(context),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            alignment: Alignment.centerLeft,
            foregroundColor: SessionColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: SessionColors.border),
            ),
          ),
          child: Semantics(
            label: 'Session length, $value. Change.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BlockLabel('LENGTH', size: 12),
                const SizedBox(height: 2),
                Text(value, style: SessionText.control.copyWith(fontFeatures: SessionText.tabular.fontFeatures)),
              ],
            ),
          ),
        ),
        if (c.showLengthNote) ...[
          const SizedBox(height: 8),
          Text('Length applies next session.', style: SessionText.weight(13, 400, color: SessionColors.secondary)),
        ],
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton(this.c);
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final playing = c.phase == SessionPhase.playing;
    final enabled = c.canPlay;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 80,
          child: IconButton.filled(
            onPressed: enabled ? c.playOrStop : null,
            style: IconButton.styleFrom(
              backgroundColor: SessionColors.primary,
              foregroundColor: SessionColors.background,
              disabledBackgroundColor: SessionColors.surface,
              disabledForegroundColor: SessionColors.secondary,
              side: enabled ? null : const BorderSide(color: SessionColors.border),
              shape: const CircleBorder(),
            ),
            icon: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: playing ? 34 : 40,
              semanticLabel: playing ? 'Stop' : 'Play',
            ),
          ),
        ),
        if (!enabled) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 140,
            child: Text(
              'Turn on a sound to play.',
              textAlign: TextAlign.center,
              style: SessionText.weight(13, 400, color: SessionColors.secondary),
            ),
          ),
        ],
      ],
    );
  }
}
