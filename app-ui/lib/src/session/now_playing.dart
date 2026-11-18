/// System now-playing for the session. Spec #9 §7.
///
/// The app pushes the metadata and the playback state itself. Pause from the
/// system ends the session the same way the screen's Stop does. The surface
/// is cleared when the session ends; a headphones pause stays up, paused.
library;

import 'package:flutter_media_session/flutter_media_session.dart';

import '../app_name.dart';
import 'session_controller.dart';

/// What [NowPlaying] needs from the system media session.
abstract interface class NowPlayingPort {
  Future<void> activate();
  Future<void> deactivate();
  void setHandlers({required void Function() onPlay, required void Function() onPause});
  Future<void> show({
    required String title,
    required String subtitle,
    required Duration? duration,
    required Duration position,
    required bool playing,
  });
}

/// [NowPlayingPort] over `flutter_media_session`.
final class FlutterNowPlaying implements NowPlayingPort {
  final FlutterMediaSession _session = FlutterMediaSession();

  @override
  Future<void> activate() => _session.activate();

  @override
  Future<void> deactivate() => _session.deactivate();

  @override
  void setHandlers({required void Function() onPlay, required void Function() onPause}) {
    _session.setActionHandler(onPlay: onPlay, onPause: onPause, onStop: onPause);
  }

  @override
  Future<void> show({
    required String title,
    required String subtitle,
    required Duration? duration,
    required Duration position,
    required bool playing,
  }) async {
    await FlutterMediaSessionPlatform.instance.updateMetadata(
      MediaMetadata(title: title, artist: subtitle, duration: duration),
    );
    await FlutterMediaSessionPlatform.instance.updatePlaybackState(
      PlaybackState(
        status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: duration == null ? Duration.zero : position,
        speed: playing && duration != null ? 1 : 0,
      ),
    );
    await FlutterMediaSessionPlatform.instance.updateAvailableActions({
      MediaAction.play,
      MediaAction.pause,
    });
  }
}

class _Shown {
  const _Shown({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.position,
    required this.playing,
  });

  final String title;
  final String subtitle;
  final Duration? duration;
  final Duration position;
  final bool playing;

  @override
  bool operator ==(Object other) =>
      other is _Shown &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.duration == duration &&
      other.position == position &&
      other.playing == playing;

  @override
  int get hashCode => Object.hash(title, subtitle, duration, position, playing);
}

/// Keeps the system surface in step with [controller].
class NowPlaying {
  NowPlaying(this.controller, this.port, {this.title = appName}) {
    controller.addListener(_sync);
  }

  final SessionController controller;
  final NowPlayingPort port;
  final String title;

  bool _active = false;
  _Shown? _shown;
  Future<void> _tail = Future<void>.value();

  void _sync() {
    _tail = _tail.then((_) => _push());
  }

  Future<void> _push() async {
    if (controller.phase == SessionPhase.stopped) {
      if (!_active) return;
      _active = false;
      _shown = null;
      await port.deactivate();
      return;
    }

    if (!_active) {
      await port.activate();
      if (controller.phase == SessionPhase.stopped) {
        await port.deactivate();
        return;
      }
      port.setHandlers(onPlay: controller.systemPlay, onPause: controller.systemPause);
      _active = true;
    }

    final duration = controller.sessionDuration;
    final shown = _Shown(
      title: title,
      subtitle: controller.soundName,
      duration: duration,
      position: duration == null ? Duration.zero : controller.sessionPosition,
      playing: controller.phase == SessionPhase.playing,
    );
    if (shown == _shown) return;
    _shown = shown;
    await port.show(
      title: shown.title,
      subtitle: shown.subtitle,
      duration: shown.duration,
      position: shown.position,
      playing: shown.playing,
    );
  }

  void dispose() {
    controller.removeListener(_sync);
    if (_active) {
      _active = false;
      port.deactivate();
    }
  }
}
