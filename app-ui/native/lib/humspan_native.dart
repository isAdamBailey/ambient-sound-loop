/// Dart wrapper over the native audio layer: `humspan_player.h` (engine plus
/// output stream) and the `humspan_engine.h` control calls.
///
/// Every call here goes straight to C on the calling thread. Call them only
/// from the Flutter UI isolate, which is the engine's one control thread.
library;

import 'dart:ffi';

import 'src/humspan_native_bindings.g.dart' as c;

/// Noise colors, matching `humspan_noise_color`.
enum NoiseColor {
  white(c.humspan_noise_color.HUMSPAN_NOISE_WHITE),
  pink(c.humspan_noise_color.HUMSPAN_NOISE_PINK),
  brown(c.humspan_noise_color.HUMSPAN_NOISE_BROWN);

  const NoiseColor(this._native);
  final c.humspan_noise_color _native;
}

/// Bits returned by [NativePlayer.takeEvents] (`HUMSPAN_PLAYER_EVENT_*`).
abstract final class PlayerEvent {
  static const rerouted = 1;
  static const finished = 2;
  static const interruptionBegan = 4;
  static const interruptionEnded = 8;
}

/// The engine owned by a [NativePlayer].
final class NativeEngine {
  NativeEngine._(this._ptr);
  final Pointer<c.humspan_engine> _ptr;

  void setNoiseColor(NoiseColor color) =>
      c.humspan_engine_set_noise_color(_ptr, color._native);
  void setVolume(double volume) => c.humspan_engine_set_volume(_ptr, volume);
  void setDuckGain(double gain) => c.humspan_engine_set_duck_gain(_ptr, gain);
  void setBinaural(bool enabled) =>
      c.humspan_engine_set_binaural(_ptr, enabled ? 1 : 0);
  void setBeatFrequency(double hz) =>
      c.humspan_engine_set_beat_frequency(_ptr, hz);
  void setBoom(bool enabled) => c.humspan_engine_set_boom(_ptr, enabled ? 1 : 0);
  void setBoomInterval(double seconds) =>
      c.humspan_engine_set_boom_interval(_ptr, seconds);

  /// [duration] <= 0 plays until stopped. False if the command queue is full.
  bool start({
    required double duration,
    required double fadeIn,
    required double fadeOut,
  }) => c.humspan_engine_start(_ptr, duration, fadeIn, fadeOut) != 0;
  bool stop({required double fade}) => c.humspan_engine_stop(_ptr, fade) != 0;
  bool pause({required double fade}) =>
      c.humspan_engine_pause(_ptr, fade) != 0;
  bool resume({required double fadeIn}) =>
      c.humspan_engine_resume(_ptr, fadeIn) != 0;

  bool get isPlaying => c.humspan_engine_is_playing(_ptr) != 0;
  bool get isPaused => c.humspan_engine_is_paused(_ptr) != 0;
  double get elapsedSeconds => c.humspan_engine_elapsed_seconds(_ptr);

  /// Negative for a session that plays until stopped; 0 when idle.
  double get remainingSeconds => c.humspan_engine_remaining_seconds(_ptr);

  /// Renders [frames] stereo frames into [out] on the calling thread. Only for
  /// tests, and only while no stream is open: in the app the output stream
  /// calls render on the audio thread.
  bool renderForTesting(Pointer<Float> out, int frames) =>
      c.humspan_engine_render(_ptr, out, frames) != 0;
}

/// One engine plus the platform's audio output stream.
final class NativePlayer {
  NativePlayer._(this._ptr) : engine = NativeEngine._(c.humspan_player_engine(_ptr));

  /// Throws [StateError] if the audio system cannot be initialised.
  factory NativePlayer.create({required int seed}) {
    final ptr = c.humspan_player_create(seed);
    if (ptr == nullptr) {
      throw StateError('Could not initialise the audio system');
    }
    return NativePlayer._(ptr);
  }

  final Pointer<c.humspan_player> _ptr;
  final NativeEngine engine;
  bool _disposed = false;

  /// Opens (or restarts) the output stream. True if it is running.
  bool open() => c.humspan_player_open(_ptr) != 0;

  /// Closes the output stream so the device can idle.
  void close() => c.humspan_player_close(_ptr);

  bool get isRunning => c.humspan_player_is_running(_ptr) != 0;

  /// [PlayerEvent] bits since the last call.
  int takeEvents() => c.humspan_player_take_events(_ptr);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    c.humspan_player_destroy(_ptr);
  }
}
