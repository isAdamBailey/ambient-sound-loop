// Smoke test: the build hook produces a loadable library and the bindings
// drive the real engine. Audio is rendered by hand, so no device is needed.
import 'dart:ffi';

import 'package:humspan_native/humspan_native.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  test('a timed session renders and counts down without an audio device', () {
    final player = NativePlayer.create(seed: 1);
    addTearDown(player.dispose);
    final engine = player.engine;

    engine.setNoiseColor(NoiseColor.brown);
    engine.setVolume(0.3);
    expect(engine.start(duration: 2.0, fadeIn: 0.1, fadeOut: 0.5), isTrue);

    // One second at the engine's initial 48 kHz rate.
    final buffer = calloc<Float>(2 * 48000);
    addTearDown(() => calloc.free(buffer));
    expect(engine.renderForTesting(buffer, 48000), isTrue);

    var peak = 0.0;
    for (var i = 0; i < 2 * 48000; i++) {
      final v = buffer[i].abs();
      if (v > peak) peak = v;
    }
    expect(peak, greaterThan(0.01));
    expect(engine.isPlaying, isTrue);
    expect(engine.elapsedSeconds, closeTo(1.0, 1e-6));
    expect(engine.remainingSeconds, closeTo(1.0, 1e-6));

    // The rest of the session, including its fade-out, then it finishes.
    engine.renderForTesting(buffer, 48000);
    expect(engine.renderForTesting(buffer, 480), isFalse);
    expect(engine.isPlaying, isFalse);
    expect(player.takeEvents(), 0, reason: 'no stream was opened');
  });

  test('pause holds the timer and resume continues it', () {
    final player = NativePlayer.create(seed: 2);
    addTearDown(player.dispose);
    final engine = player.engine;
    final buffer = calloc<Float>(2 * 4800);
    addTearDown(() => calloc.free(buffer));

    engine.start(duration: 60, fadeIn: 0, fadeOut: 0);
    engine.renderForTesting(buffer, 4800); // 0.1 s
    engine.pause(fade: 0);
    engine.renderForTesting(buffer, 4800);
    engine.renderForTesting(buffer, 4800);
    expect(engine.isPaused, isTrue);
    final held = engine.elapsedSeconds;

    engine.renderForTesting(buffer, 4800);
    expect(engine.elapsedSeconds, held);

    engine.resume(fadeIn: 0);
    engine.renderForTesting(buffer, 4800);
    expect(engine.isPaused, isFalse);
    expect(engine.elapsedSeconds, greaterThan(held));
  });
}
