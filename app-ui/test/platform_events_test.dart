import 'package:ambient_app/src/session/platform_events.dart';
import 'package:ambient_app/src/session/session_controller.dart';
import 'package:ambient_app/src/session/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio.dart';

void main() {
  test('platform calls map onto ducking, headphones-out and stop', () {
    final audio = FakeAudio();
    final controller = SessionController(
      audio: audio,
      settings: SessionSettings.firstLaunch,
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: (_) {},
    );
    controller.playOrStop();
    audio.calls.clear();

    applySessionEvent(controller, 'focusTransient');
    expect(audio.calls, ['duck 0.0']);
    expect(controller.phase, SessionPhase.playing);

    applySessionEvent(controller, 'focusGain');
    expect(audio.calls.last, 'duck 1.0');

    applySessionEvent(controller, 'focusDuck');
    expect(audio.calls.last, 'duck 0.3');

    applySessionEvent(controller, 'outputLost');
    expect(controller.phase, SessionPhase.paused);

    controller.playOrStop();
    applySessionEvent(controller, 'focusLoss');
    expect(controller.phase, SessionPhase.stopped);

    applySessionEvent(controller, 'unused');
    expect(controller.phase, SessionPhase.stopped);
    controller.dispose();
  });
}
