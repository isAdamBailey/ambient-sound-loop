/// What the session controller needs from the native audio layer: the engine
/// controls from `ambient_engine.h` plus the output stream from
/// `ambient_player.h`. [FfiAudioPort] is the real one; tests use a fake.
library;

import 'package:ambient_native/ambient_native.dart';

abstract interface class AudioPort {
  void setColor(NoiseColor color);
  void setVolume(double volume); // 0–1
  void setDuckGain(double gain); // 0–1, 1 = no duck
  void setBinaural(bool enabled);
  void setBeatFrequency(double hz);

  bool start({required double duration, required double fadeIn, required double fadeOut});
  bool stop({required double fade});
  bool pause({required double fade});
  bool resume({required double fadeIn});

  bool get isPlaying;
  bool get isPaused;
  double get elapsedSeconds;
  double get remainingSeconds;

  bool openStream();
  void closeStream();
  bool get isStreamRunning;

  /// [PlayerEvent] bits since the last call.
  int takeEvents();
}

/// [AudioPort] over the native player.
final class FfiAudioPort implements AudioPort {
  FfiAudioPort(this._player);

  final NativePlayer _player;
  NativeEngine get _engine => _player.engine;

  @override
  void setColor(NoiseColor color) => _engine.setNoiseColor(color);
  @override
  void setVolume(double volume) => _engine.setVolume(volume);
  @override
  void setDuckGain(double gain) => _engine.setDuckGain(gain);
  @override
  void setBinaural(bool enabled) => _engine.setBinaural(enabled);
  @override
  void setBeatFrequency(double hz) => _engine.setBeatFrequency(hz);

  @override
  bool start({required double duration, required double fadeIn, required double fadeOut}) =>
      _engine.start(duration: duration, fadeIn: fadeIn, fadeOut: fadeOut);
  @override
  bool stop({required double fade}) => _engine.stop(fade: fade);
  @override
  bool pause({required double fade}) => _engine.pause(fade: fade);
  @override
  bool resume({required double fadeIn}) => _engine.resume(fadeIn: fadeIn);

  @override
  bool get isPlaying => _engine.isPlaying;
  @override
  bool get isPaused => _engine.isPaused;
  @override
  double get elapsedSeconds => _engine.elapsedSeconds;
  @override
  double get remainingSeconds => _engine.remainingSeconds;

  @override
  bool openStream() => _player.open();
  @override
  void closeStream() => _player.close();
  @override
  bool get isStreamRunning => _player.isRunning;

  @override
  int takeEvents() => _player.takeEvents();
}
