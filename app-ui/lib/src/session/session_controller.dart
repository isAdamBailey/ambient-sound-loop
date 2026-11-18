/// The session: Play/Stop, pause on headphones out, ducking, the clock, and
/// the settings that drive the engine. Spec #9 §2 and §5.
///
/// Every method runs on the UI isolate, which is the engine's control thread.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:ambient_native/ambient_native.dart';
import 'package:flutter/foundation.dart';

import 'audio_port.dart';
import 'length.dart';
import 'settings.dart';

enum SessionPhase {
  stopped,
  playing,

  /// Held after headphones or Bluetooth went away. Play resumes it.
  paused,
}

/// How a device reroute reported by the native stream is handled.
enum RerouteBehavior {
  /// Desktop: the OS gives no "headphones out" signal, so any change of
  /// output device pauses, and sound never moves to the speaker by itself.
  pauseSession,

  /// Android: the platform glue reports headphones out; the stream stops on
  /// every reroute and is restarted here only while the session plays.
  restartStream,

  /// iOS: the platform glue reports headphones out; the stream follows the
  /// route by itself.
  ignore,
}

/// An audio focus loss (Android) or interruption.
enum FocusLoss {
  /// A phone call or similar: silence, keep the session and its clock.
  transient,

  /// A short system sound, e.g. navigation: lower the sound.
  canDuck,

  /// Another app started playing media: end the session.
  permanent,
}

class SessionController extends ChangeNotifier {
  SessionController({
    required AudioPort audio,
    required SessionSettings settings,
    required this.reroute,
    required this.onSettingsChanged,
  }) : _audio = audio,
       _settings = settings {
    _audio
      ..setColor(settings.color)
      ..setVolume(settings.volumePercent / 100)
      ..setBinaural(settings.binauralOn)
      ..setBeatFrequency(settings.beatHz.toDouble());
  }

  static const fadeIn = 5.0;
  static const fadeOut = 60.0;
  static const stopFade = 1.0;
  static const pauseFade = 0.05;
  static const callDuck = 0.0;
  static const shortDuck = 0.3;
  static const tickInterval = Duration(milliseconds: 250);

  /// How long a pause from the system waits for a headphones-out report
  /// before it is taken as the user's Stop. Both platforms' media plugins
  /// send that pause when headphones go, and the order of the two messages
  /// is not fixed.
  static const systemPauseGrace = Duration(milliseconds: 300);

  final AudioPort _audio;
  final RerouteBehavior reroute;
  final void Function(SessionSettings) onSettingsChanged;

  SessionSettings _settings;
  SessionPhase _phase = SessionPhase.stopped;
  SessionLength? _sessionLength; // the running session's own length
  bool _sawPlaying = false; // the audio thread has picked up the start
  Timer? _ticker;
  Timer? _pendingSystemPause;

  SessionSettings get settings => _settings;
  SessionPhase get phase => _phase;

  /// The length shown and used while a session runs; else the chosen one.
  SessionLength get _shownLength =>
      _phase == SessionPhase.stopped ? _settings.length : (_sessionLength ?? _settings.length);

  /// `H:MM:SS`: remaining for a timed session, elapsed for Until I stop; when
  /// stopped, the chosen length (or 0:00:00 for Until I stop).
  String get clockText => formatClock(_clockSeconds);

  int get _clockSeconds {
    final length = _shownLength;
    if (_phase == SessionPhase.stopped || !_sawPlaying) {
      return length.duration?.inSeconds ?? 0;
    }
    if (length is UntilStop) return _audio.elapsedSeconds.floor();
    return math.max(0, _audio.remainingSeconds.ceil());
  }

  String get clockCaption => switch ((_phase, _shownLength)) {
    (SessionPhase.stopped, UntilStop()) => 'until you stop',
    (SessionPhase.stopped, _) => 'session length',
    (_, UntilStop()) => 'elapsed',
    _ => 'left',
  };

  /// "Length applies next session." while one is running.
  bool get showLengthNote => _phase != SessionPhase.stopped;

  /// The sound, for the system now-playing subtitle.
  String get soundName {
    final color = switch (_settings.color) {
      NoiseColor.white => 'White',
      NoiseColor.pink => 'Pink',
      NoiseColor.brown => 'Brown',
    };
    return _settings.binauralOn ? '$color noise · ${_settings.beatHz} Hz beat' : '$color noise';
  }

  /// The running timed session's length, for the now-playing progress bar.
  Duration? get sessionDuration => _phase == SessionPhase.stopped ? null : _sessionLength?.duration;

  /// Rendered time of the running session.
  Duration get sessionPosition => _phase == SessionPhase.stopped || !_sawPlaying
      ? Duration.zero
      : Duration(milliseconds: (_audio.elapsedSeconds * 1000).round());

  // --- Play/Stop ---

  /// The round button: Play when stopped or paused, Stop when playing.
  void playOrStop() => _phase == SessionPhase.playing ? stop() : play();

  void play() {
    switch (_phase) {
      case SessionPhase.playing:
        return;
      case SessionPhase.paused:
        if (!_audio.isStreamRunning && !_audio.openStream()) return;
        _audio.resume(fadeIn: fadeIn);
      case SessionPhase.stopped:
        _audio.setDuckGain(1);
        if (!_audio.openStream()) return;
        final length = _settings.length;
        _audio.start(
          duration: (length.duration?.inMilliseconds ?? 0) / 1000,
          fadeIn: fadeIn,
          fadeOut: fadeOut,
        );
        _sessionLength = length;
        _sawPlaying = false;
    }
    _phase = SessionPhase.playing;
    _ensureTicking();
    notifyListeners();
  }

  void stop() {
    if (_phase == SessionPhase.stopped) return;
    _pendingSystemPause?.cancel();
    _audio.stop(fade: stopFade);
    _phase = SessionPhase.stopped;
    _ensureTicking(); // closes the stream once the fade has finished
    notifyListeners();
  }

  // --- Platform events ---

  /// Headphones or Bluetooth went away.
  void routeLost() {
    if (_phase != SessionPhase.playing) return;
    _audio.pause(fade: pauseFade);
    _phase = SessionPhase.paused;
    notifyListeners();
  }

  /// Play from the lock screen, a headset or the system media controls.
  void systemPlay() => play();

  /// Pause from the system: ends the session like Stop, unless it is the
  /// echo of headphones going away.
  void systemPause() {
    if (_phase != SessionPhase.playing) return;
    _pendingSystemPause?.cancel();
    _pendingSystemPause = Timer(systemPauseGrace, () {
      if (_phase == SessionPhase.playing) stop();
    });
  }

  void focusLost(FocusLoss loss) {
    if (_phase == SessionPhase.stopped) return;
    switch (loss) {
      case FocusLoss.transient:
        _audio.setDuckGain(callDuck);
      case FocusLoss.canDuck:
        _audio.setDuckGain(shortDuck);
      case FocusLoss.permanent:
        stop();
    }
  }

  void focusGained() => _audio.setDuckGain(1);

  // --- Settings ---

  void setColor(NoiseColor color) {
    _audio.setColor(color);
    _update(_settings.copyWith(color: color));
  }

  void setVolume(int percent) {
    final p = percent.clamp(0, 100);
    _audio.setVolume(p / 100);
    _update(_settings.copyWith(volumePercent: p));
  }

  void setBinaural(bool on) {
    _audio.setBinaural(on);
    _update(_settings.copyWith(binauralOn: on));
  }

  /// The beat chip: the next frequency in [beatFrequencies], wrapping.
  void nextBeat() {
    final i = beatFrequencies.indexOf(_settings.beatHz);
    final hz = beatFrequencies[(i + 1) % beatFrequencies.length];
    _audio.setBeatFrequency(hz.toDouble());
    _update(_settings.copyWith(beatHz: hz));
  }

  /// Takes effect at the next session.
  void setLength(SessionLength length) => _update(_settings.copyWith(length: length));

  void _update(SessionSettings next) {
    if (next == _settings) return;
    _settings = next;
    onSettingsChanged(next);
    notifyListeners();
  }

  // --- Polling the engine ---

  void _ensureTicking() => _ticker ??= Timer.periodic(tickInterval, (_) => _tick());

  void _tick() {
    final events = _audio.takeEvents();
    final playing = _audio.isPlaying;
    if (playing) _sawPlaying = true;
    final finished = (events & PlayerEvent.finished) != 0 || (_sawPlaying && !playing);

    if ((events & PlayerEvent.rerouted) != 0) _onRerouted();

    if (finished) {
      _audio.closeStream();
      _sawPlaying = false;
      if (_phase != SessionPhase.stopped) {
        _pendingSystemPause?.cancel();
        _phase = SessionPhase.stopped;
      }
    }

    if (_phase == SessionPhase.stopped && !_audio.isStreamRunning) {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  void _onRerouted() {
    switch (reroute) {
      case RerouteBehavior.pauseSession:
        routeLost();
      case RerouteBehavior.restartStream:
        if (_phase == SessionPhase.playing && !_audio.isStreamRunning) _audio.openStream();
      case RerouteBehavior.ignore:
        break;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pendingSystemPause?.cancel();
    super.dispose();
  }
}

/// `H:MM:SS`.
String formatClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600, m = (totalSeconds % 3600) ~/ 60, s = totalSeconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
