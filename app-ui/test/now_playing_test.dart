import 'package:humspan/src/app_name.dart';
import 'package:humspan/src/session/length.dart';
import 'package:humspan/src/session/now_playing.dart';
import 'package:humspan/src/session/session_controller.dart';
import 'package:humspan/src/session/settings.dart';
import 'package:humspan_native/humspan_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio.dart';

class _Port implements NowPlayingPort {
  final calls = <String>[];
  String? title, subtitle;
  Duration? duration, position;
  bool? playing;

  @override
  Future<void> activate() async => calls.add('activate');

  @override
  Future<void> deactivate() async => calls.add('deactivate');

  @override
  void setHandlers({required void Function() onPlay, required void Function() onPause}) {
    calls.add('handlers');
    this.onPlay = onPlay;
    this.onPause = onPause;
  }

  void Function()? onPlay, onPause;

  @override
  Future<void> show({
    required String title,
    required String subtitle,
    required Duration? duration,
    required Duration position,
    required bool playing,
  }) async {
    calls.add('show');
    this.title = title;
    this.subtitle = subtitle;
    this.duration = duration;
    this.position = position;
    this.playing = playing;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('publishes the sound while playing and clears the surface when it ends', () async {
    final audio = FakeAudio();
    final controller = SessionController(
      audio: audio,
      settings: SessionSettings.firstLaunch,
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: (_) {},
    );
    final port = _Port();
    final now = NowPlaying(controller, port);

    controller.playOrStop();
    await _settle();
    expect(port.calls, ['activate', 'handlers', 'show']);
    expect(port.title, appName);
    expect(port.subtitle, 'Pink noise');
    expect(port.duration, const Duration(hours: 8));
    expect(port.playing, isTrue);

    controller.setBinaural(true);
    await _settle();
    expect(port.subtitle, 'Pink noise · 4 Hz beat');

    controller.setBoom(true);
    await _settle();
    expect(port.subtitle, 'Pink noise · 4 Hz beat · boom');

    controller.playOrStop();
    await _settle();
    expect(port.calls.last, 'deactivate');

    now.dispose();
    controller.dispose();
  });

  test('Until I stop publishes no duration', () async {
    final controller = SessionController(
      audio: FakeAudio(),
      settings: SessionSettings.firstLaunch.copyWith(length: SessionLength.untilStop),
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: (_) {},
    );
    final port = _Port();
    NowPlaying(controller, port);
    controller.playOrStop();
    await _settle();
    expect(port.duration, isNull);
    expect(port.position, Duration.zero);
    controller.dispose();
  });

  test('a headphones pause stays on the surface, paused, and play there resumes', () async {
    final audio = FakeAudio();
    final controller = SessionController(
      audio: audio,
      settings: SessionSettings.firstLaunch,
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: (_) {},
    );
    final port = _Port();
    NowPlaying(controller, port);
    controller.playOrStop();
    await _settle();
    port.calls.clear();

    controller.routeLost();
    await _settle();
    expect(port.calls, ['show']);
    expect(port.playing, isFalse);
    expect(port.calls, isNot(contains('deactivate')));

    port.onPlay!();
    expect(controller.phase, SessionPhase.playing);
    controller.dispose();
  });
}
