import 'package:humspan/src/session/audio_port.dart';
import 'package:humspan_native/humspan_native.dart';

/// Stands in for the native engine and stream. Tests move the engine's state
/// by hand, the way the audio thread would.
class FakeAudio implements AudioPort {
  final calls = <String>[];
  bool playing = false, paused = false, running = false, openSucceeds = true;
  double elapsed = 0, remaining = 0;
  int events = 0;

  @override
  void setColor(NoiseColor color) => calls.add('color ${color.name}');
  @override
  void setVolume(double volume) => calls.add('volume $volume');
  @override
  void setDuckGain(double gain) => calls.add('duck $gain');
  @override
  void setNoise(bool enabled) => calls.add('noise $enabled');
  @override
  void setNoiseLevel(double gain) => calls.add('noise-level $gain');
  @override
  void setBinauralLevel(double gain) => calls.add('binaural-level $gain');
  @override
  void setBoomLevel(double gain) => calls.add('boom-level $gain');
  @override
  void setBinaural(bool enabled) => calls.add('binaural $enabled');
  @override
  void setBeatFrequency(double hz) => calls.add('beat $hz');
  @override
  void setBoom(bool enabled) => calls.add('boom $enabled');
  @override
  void setBoomInterval(double seconds) => calls.add('boom-interval $seconds');
  @override
  void setSpeakerOutput(bool speaker) => calls.add('speaker $speaker');
  @override
  bool start({required double duration, required double fadeIn, required double fadeOut}) {
    calls.add('start $duration $fadeIn $fadeOut');
    return true;
  }

  @override
  bool stop({required double fade}) {
    calls.add('stop $fade');
    return true;
  }

  @override
  bool pause({required double fade}) {
    calls.add('pause $fade');
    return true;
  }

  @override
  bool resume({required double fadeIn}) {
    calls.add('resume $fadeIn');
    return true;
  }

  @override
  bool get isPlaying => playing;
  @override
  bool get isPaused => paused;
  @override
  double get elapsedSeconds => elapsed;
  @override
  double get remainingSeconds => remaining;
  @override
  bool openStream() {
    calls.add('open');
    running = openSucceeds;
    return openSucceeds;
  }

  @override
  void closeStream() {
    calls.add('close');
    running = false;
  }

  @override
  bool get isStreamRunning => running;
  @override
  int takeEvents() {
    final e = events;
    events = 0;
    return e;
  }

  /// The audio thread picked up the start command.
  void beginSession({required double remaining}) {
    playing = true;
    this.remaining = remaining;
  }

  /// The session ran out (or its stop fade finished).
  void finishSession() {
    playing = false;
    paused = false;
    remaining = 0;
    events |= PlayerEvent.finished;
  }
}
