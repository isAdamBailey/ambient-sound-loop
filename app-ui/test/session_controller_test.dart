import 'package:humspan/src/session/length.dart';
import 'package:humspan/src/session/session_controller.dart';
import 'package:humspan/src/session/settings.dart';
import 'package:humspan_native/humspan_native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio.dart';

const tick = SessionController.tickInterval;

void main() {
  late FakeAudio audio;
  late List<SessionSettings> saved;

  SessionController make({
    SessionSettings settings = SessionSettings.firstLaunch,
    RerouteBehavior reroute = RerouteBehavior.ignore,
  }) {
    saved = [];
    return SessionController(
      audio: audio,
      settings: settings,
      reroute: reroute,
      onSettingsChanged: saved.add,
    );
  }

  setUp(() => audio = FakeAudio());

  test('opens stopped on the restored settings and applies them to the engine', () {
    final c = make(settings: SessionSettings.firstLaunch.copyWith(color: NoiseColor.brown));
    expect(c.phase, SessionPhase.stopped);
    expect(audio.calls, containsAll([
      'noise true', 'color brown', 'volume 1.0', 'binaural false', 'beat 4.0', 'boom false',
      'boom-interval 8.0', 'noise-level 1.0', 'binaural-level 1.0', 'boom-level 1.0',
    ]));
    expect(audio.calls.where((s) => s.startsWith('start') || s == 'open'), isEmpty,
        reason: 'never plays sound on launch');
  });

  group('stopped clock', () {
    test('shows the chosen length', () {
      final c = make(settings: SessionSettings.firstLaunch.copyWith(
          length: SessionLength.timed(const Duration(hours: 1, minutes: 37))));
      expect(c.clockText, '1:37:00');
      expect(c.clockCaption, 'session length');
    });

    test('shows 0:00:00 for Until I stop', () {
      final c = make(settings: SessionSettings.firstLaunch.copyWith(length: SessionLength.untilStop));
      expect(c.clockText, '0:00:00');
      expect(c.clockCaption, 'until you stop');
    });
  });

  test('Play starts a timed session with 5 s fade-in and 1 min fade-out', () {
    fakeAsync((async) {
      final c = make(settings: SessionSettings.firstLaunch.copyWith(
          length: SessionLength.timed(const Duration(minutes: 90))));
      audio.calls.clear();
      c.playOrStop();
      expect(audio.calls, ['duck 1.0', 'open', 'start 5400.0 5.0 60.0']);
      expect(c.phase, SessionPhase.playing);
      expect(c.clockText, '1:30:00', reason: 'before the audio thread reports in');

      audio.beginSession(remaining: 5399.2);
      async.elapse(tick);
      expect(c.clockText, '1:30:00', reason: 'counts down by whole seconds, rounding up');
      expect(c.clockCaption, 'left');
      audio.remaining = 5398.9;
      async.elapse(tick);
      expect(c.clockText, '1:29:59');
      c.dispose();
    });
  });

  test('Until I stop starts with no duration and its clock counts up', () {
    fakeAsync((async) {
      final c = make(settings: SessionSettings.firstLaunch.copyWith(length: SessionLength.untilStop));
      audio.calls.clear();
      c.playOrStop();
      expect(audio.calls.last, 'start 0.0 5.0 60.0');
      audio.beginSession(remaining: -1);
      audio.elapsed = 3725.6;
      async.elapse(tick);
      expect(c.clockText, '1:02:05');
      expect(c.clockCaption, 'elapsed');
      c.dispose();
    });
  });

  test('a session that cannot open the stream stays stopped', () {
    final c = make();
    audio.openSucceeds = false;
    c.playOrStop();
    expect(c.phase, SessionPhase.stopped);
    expect(audio.calls.where((s) => s.startsWith('start')), isEmpty);
  });

  test('Stop fades over 1 s; the screen stops at once and the stream closes after the fade', () {
    fakeAsync((async) {
      final c = make();
      c.playOrStop();
      audio.beginSession(remaining: 100);
      async.elapse(tick);
      audio.calls.clear();

      c.playOrStop();
      expect(audio.calls, ['stop 1.0']);
      expect(c.phase, SessionPhase.stopped);
      expect(c.clockText, '8:00:00');
      async.elapse(tick);
      expect(audio.running, isTrue, reason: 'the stop fade is still playing');

      audio.finishSession();
      async.elapse(tick);
      expect(audio.calls.last, 'close');
      c.dispose();
    });
  });

  test('the end of a timed session returns to stopped and closes the stream', () {
    fakeAsync((async) {
      final c = make();
      var notified = 0;
      c.addListener(() => notified++);
      c.playOrStop();
      audio.beginSession(remaining: 0.2);
      async.elapse(tick);
      audio.finishSession();
      async.elapse(tick);
      expect(c.phase, SessionPhase.stopped);
      expect(audio.running, isFalse);
      expect(notified, greaterThan(0));
      c.dispose();
    });
  });

  test('a length change waits for the next session', () {
    fakeAsync((async) {
      final c = make();
      c.playOrStop();
      audio.beginSession(remaining: 28000);
      async.elapse(tick);
      expect(c.lengthLocked, isTrue);

      c.setLength(SessionLength.untilStop);
      expect(saved.last.length, SessionLength.untilStop);
      expect(c.clockCaption, 'left', reason: 'the running session keeps its own length');
      expect(audio.calls.where((s) => s.startsWith('start')), hasLength(1));

      c.playOrStop();
      audio.finishSession();
      async.elapse(tick);
      expect(c.lengthLocked, isFalse);
      c.playOrStop();
      expect(audio.calls.last, 'start 0.0 5.0 60.0');
      c.dispose();
    });
  });

  test('color and binaural apply at once, also mid-session, and are saved', () {
    final c = make();
    c.playOrStop();
    audio.calls.clear();
    c.setColor(NoiseColor.white);
    c.setBinaural(true);
    c.setBeatHz(6);
    expect(audio.calls, ['color white', 'binaural true', 'beat 6.0']);
    expect(saved.last, SessionSettings.firstLaunch.copyWith(
        color: NoiseColor.white, binauralOn: true, beatHz: 6));
    c.dispose();
  });

  test('the beat stepper sets one of 2, 4, 6, 8, 10 Hz', () {
    final c = make();
    for (final hz in beatFrequencies) {
      c.setBeatHz(hz);
      expect(c.settings.beatHz, hz);
      expect(audio.calls.last, 'beat $hz.0');
    }
  });

  test('the boom gap sets 8, 4 or 2 seconds and the boom can be switched off', () {
    final c = make();
    c.setBoom(true);
    expect(c.settings.boomOn, isTrue);
    expect(audio.calls, contains('boom true'));
    for (final seconds in [4, 2, 8]) {
      c.setBoomSeconds(seconds);
      expect(c.settings.boomSeconds, seconds);
    }
    expect(c.soundName, 'Pink noise · boom');
    c.setBinaural(true);
    expect(c.soundName, 'Pink noise · 4 Hz beat · boom');
    c.setBoom(false);
    expect(c.soundName, 'Pink noise · 4 Hz beat');
    c.dispose();
  });

  group('headphones out', () {
    test('pauses with a quick fade; Play resumes the same session with a 5 s fade-in', () {
      fakeAsync((async) {
        final c = make();
        c.playOrStop();
        audio.beginSession(remaining: 3000);
        async.elapse(tick);
        audio.calls.clear();

        c.routeLost();
        expect(audio.calls, ['pause 0.05']);
        expect(c.phase, SessionPhase.paused);
        audio.paused = true;
        audio.remaining = 2999;
        async.elapse(tick);
        expect(c.clockText, '0:49:59');

        c.playOrStop();
        expect(audio.calls.last, 'resume 5.0');
        expect(c.phase, SessionPhase.playing);
        expect(audio.calls.where((s) => s.startsWith('start')), isEmpty);
        c.dispose();
      });
    });

    test("the system's pause that comes with it does not end the session", () {
      fakeAsync((async) {
        final c = make();
        c.playOrStop();
        audio.beginSession(remaining: 3000);
        async.elapse(tick);

        c.systemPause(); // the plugin's echo can arrive first
        c.routeLost();
        async.elapse(const Duration(seconds: 1));
        expect(c.phase, SessionPhase.paused);
        expect(audio.calls.where((s) => s.startsWith('stop')), isEmpty);

        c.systemPause();
        async.elapse(const Duration(seconds: 1));
        expect(c.phase, SessionPhase.paused);
        c.dispose();
      });
    });

    test('Stop while paused ends the session', () {
      final c = make();
      c.playOrStop();
      c.routeLost();
      c.stop();
      expect(c.phase, SessionPhase.stopped);
      expect(audio.calls.last, 'stop 1.0');
      c.dispose();
    });

    test('when stopped it does nothing', () {
      final c = make();
      c.routeLost();
      expect(c.phase, SessionPhase.stopped);
      expect(audio.calls.where((s) => s.startsWith('pause')), isEmpty);
    });
  });

  group('lock screen and system controls', () {
    test('pause from the system ends the session like Stop', () {
      fakeAsync((async) {
        final c = make();
        c.playOrStop();
        c.systemPause();
        async.elapse(const Duration(seconds: 1));
        expect(c.phase, SessionPhase.stopped);
        expect(audio.calls.last, 'stop 1.0');
        c.dispose();
      });
    });

    test('play from the system starts or resumes', () {
      final c = make();
      c.systemPlay();
      expect(c.phase, SessionPhase.playing);
      c.routeLost();
      c.systemPlay();
      expect(audio.calls.last, 'resume 5.0');
      c.systemPlay();
      expect(audio.calls.last, 'resume 5.0', reason: 'already playing: nothing new');
      c.dispose();
    });
  });

  group('device reroutes', () {
    test('desktop: a reroute pauses the session', () {
      fakeAsync((async) {
        final c = make(reroute: RerouteBehavior.pauseSession);
        c.playOrStop();
        audio.beginSession(remaining: 100);
        audio.events |= PlayerEvent.rerouted;
        async.elapse(tick);
        expect(c.phase, SessionPhase.paused);
        c.dispose();
      });
    });

    test('Android: the stream restarts after a reroute only while playing', () {
      fakeAsync((async) {
        final c = make(reroute: RerouteBehavior.restartStream);
        c.playOrStop();
        audio.beginSession(remaining: 100);
        async.elapse(tick);

        // Headphones in: Android stopped the stream; it comes back after the
        // wait, so a headphones-out report in that window can cancel it.
        audio.running = false;
        audio.events |= PlayerEvent.rerouted;
        audio.calls.clear();
        async.elapse(tick);
        expect(audio.calls, isEmpty);
        async.elapse(SessionController.rerouteRestartGrace);
        expect(audio.calls, ['open']);

        // Headphones out reported before the reroute: the speaker stays silent.
        c.routeLost();
        audio.running = false;
        audio.events |= PlayerEvent.rerouted;
        audio.calls.clear();
        async.elapse(tick + SessionController.rerouteRestartGrace);
        expect(audio.calls, isEmpty);

        // And when the reroute is seen first: the pending restart is dropped.
        c.playOrStop();
        audio.running = false;
        audio.events |= PlayerEvent.rerouted;
        audio.calls.clear();
        async.elapse(tick);
        c.routeLost();
        async.elapse(SessionController.rerouteRestartGrace);
        expect(audio.calls.where((s) => s == 'open'), isEmpty);
        expect(c.phase, SessionPhase.paused);

        audio.calls.clear();
        c.playOrStop();
        expect(audio.calls, ['open', 'resume 5.0']);
        c.dispose();
      });
    });
  });

  group('interruptions', () {
    test('a call ducks to silence and the session keeps its place; focus back restores it', () {
      final c = make();
      c.playOrStop();
      audio.calls.clear();
      c.focusLost(FocusLoss.transient);
      expect(audio.calls, ['duck 0.0']);
      expect(c.phase, SessionPhase.playing);
      c.focusGained();
      expect(audio.calls.last, 'duck 1.0');
      c.dispose();
    });

    test('a short system sound ducks partly', () {
      final c = make();
      c.playOrStop();
      c.focusLost(FocusLoss.canDuck);
      expect(audio.calls.last, 'duck 0.3');
      c.dispose();
    });

    test('an engine interruption ducks, and the end of it restores the level', () {
      fakeAsync((async) {
        final c = make();
        c.playOrStop();
        audio.beginSession(remaining: 100);
        audio.calls.clear();
        audio.events |= PlayerEvent.interruptionBegan;
        async.elapse(tick);
        expect(audio.calls, ['duck 0.0']);
        expect(c.phase, SessionPhase.playing);
        audio.events |= PlayerEvent.interruptionEnded;
        async.elapse(tick);
        expect(audio.calls.last, 'duck 1.0');
        c.dispose();
      });
    });

    test('another app taking over media ends the session', () {
      final c = make();
      c.playOrStop();
      c.focusLost(FocusLoss.permanent);
      expect(c.phase, SessionPhase.stopped);
      c.dispose();
    });
  });

  test('restored layer toggles and levels reach the engine', () {
    make(settings: SessionSettings.firstLaunch.copyWith(
        noiseOn: false, binauralOn: true, noiseLevel: 0.5, binauralLevel: 0, boomLevel: 0.75));
    expect(audio.calls, containsAll([
      'noise false', 'binaural true', 'noise-level ${levelGain(0.5)}', 'binaural-level ${levelGain(0)}',
      'boom-level ${levelGain(0.75)}',
    ]));
  });

  group('independent layers', () {
    test('noise toggles on its own and keeps the color', () {
      final c = make();
      audio.calls.clear();
      c.setNoise(false);
      expect(audio.calls, ['noise false']);
      expect(c.settings.noiseOn, isFalse);
      expect(c.settings.binauralOn, isFalse);
      c.setColor(NoiseColor.brown); // ready for when noise comes back
      expect(c.settings.color, NoiseColor.brown);
      expect(saved.last, SessionSettings.firstLaunch.copyWith(noiseOn: false, color: NoiseColor.brown));
    });

    test('with every layer off, Play is disabled while stopped', () {
      final c = make(settings: SessionSettings.firstLaunch.copyWith(noiseOn: false));
      expect(c.canPlay, isFalse);
      audio.calls.clear();
      c.playOrStop();
      expect(c.phase, SessionPhase.stopped);
      expect(audio.calls, isEmpty, reason: 'nothing to play');
      c.setBoom(true);
      expect(c.canPlay, isTrue);
      c.playOrStop();
      expect(c.phase, SessionPhase.playing);
      c.dispose();
    });

    test('a slider at its bottom is quiet, not off: Play stays available', () {
      final c = make();
      c.setLevel(SoundLayer.noise, 0);
      expect(c.canPlay, isTrue);
    });

    test('mid-session the last layer can go off; the session carries on in silence', () {
      fakeAsync((async) {
        final c = make();
        c.playOrStop();
        audio.beginSession(remaining: 3000);
        async.elapse(tick);
        c.setNoise(false);
        expect(c.phase, SessionPhase.playing);
        expect(c.canPlay, isTrue, reason: 'Stop stays available');
        expect(c.soundName, 'Silent');
        audio.remaining = 2990;
        async.elapse(tick);
        expect(c.clockText, '0:49:50');
        c.playOrStop();
        expect(c.phase, SessionPhase.stopped);
        expect(c.canPlay, isFalse);
        c.dispose();
      });
    });
  });

  group('level sliders', () {
    test('each step reaches the engine through the dB taper', () {
      final c = make();
      audio.calls.clear();
      c.setLevel(SoundLayer.noise, 0.5);
      c.setLevel(SoundLayer.binaural, 0.75);
      c.setLevel(SoundLayer.boom, 0);
      expect(audio.calls, [
        'noise-level ${levelGain(0.5)}',
        'binaural-level ${levelGain(0.75)}',
        'boom-level ${levelGain(0)}',
      ]);
      expect(levelGain(0.5), closeTo(0.1, 1e-12)); // -20 dB
      expect(c.settings.noiseLevel, 0.5);
      expect(c.settings.binauralLevel, 0.75);
      expect(c.settings.boomLevel, 0.0);
    });

    test('a level saves when the drag ends, not on every step', () {
      final c = make();
      c.setLevel(SoundLayer.binaural, 0.9);
      c.setLevel(SoundLayer.binaural, 0.8);
      c.setLevel(SoundLayer.binaural, 0.7);
      expect(saved, isEmpty);
      c.saveLevels();
      expect(saved, [SessionSettings.firstLaunch.copyWith(binauralLevel: 0.7)]);
      c.saveLevels();
      expect(saved, hasLength(1), reason: 'nothing new to save');
    });

    test('a level changes only its own layer', () {
      final c = make();
      audio.calls.clear();
      c.setLevel(SoundLayer.boom, 0.4);
      expect(audio.calls, ['boom-level ${levelGain(0.4)}']);
      expect(c.settings, SessionSettings.firstLaunch.copyWith(boomLevel: 0.4));
    });
  });

  test('now-playing subtitle lists only the layers that are on', () {
    final c = make();
    const cases = {
      (true, false, false): 'Pink noise',
      (true, true, false): 'Pink noise · 4 Hz beat',
      (true, false, true): 'Pink noise · boom',
      (true, true, true): 'Pink noise · 4 Hz beat · boom',
      (false, true, false): '4 Hz beat',
      (false, false, true): 'Boom',
      (false, true, true): '4 Hz beat · boom',
      (false, false, false): 'Silent',
    };
    cases.forEach((on, name) {
      c.setNoise(on.$1);
      c.setBinaural(on.$2);
      c.setBoom(on.$3);
      expect(c.soundName, name, reason: '$on');
    });
  });

  test('now-playing subtitle names the sound', () {
    final c = make();
    expect(c.soundName, 'Pink noise');
    c.setBinaural(true);
    expect(c.soundName, 'Pink noise · 4 Hz beat');
    c.setColor(NoiseColor.brown);
    expect(c.soundName, 'Brown noise · 4 Hz beat');
  });
}
