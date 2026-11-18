import 'package:ambient_app/src/session/length.dart';
import 'package:ambient_app/src/session/session_controller.dart';
import 'package:ambient_app/src/session/settings.dart';
import 'package:ambient_native/ambient_native.dart';
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
    expect(audio.calls, containsAll(['color brown', 'volume 0.3', 'binaural false', 'beat 4.0']));
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
      expect(c.showLengthNote, isTrue);

      c.setLength(SessionLength.untilStop);
      expect(saved.last.length, SessionLength.untilStop);
      expect(c.clockCaption, 'left', reason: 'the running session keeps its own length');
      expect(audio.calls.where((s) => s.startsWith('start')), hasLength(1));

      c.playOrStop();
      audio.finishSession();
      async.elapse(tick);
      expect(c.showLengthNote, isFalse);
      c.playOrStop();
      expect(audio.calls.last, 'start 0.0 5.0 60.0');
      c.dispose();
    });
  });

  test('color, volume and binaural apply at once, also mid-session, and are saved', () {
    final c = make();
    c.playOrStop();
    audio.calls.clear();
    c.setColor(NoiseColor.white);
    c.setVolume(55);
    c.setBinaural(true);
    c.nextBeat();
    expect(audio.calls, ['color white', 'volume 0.55', 'binaural true', 'beat 6.0']);
    expect(saved.last, SessionSettings.firstLaunch.copyWith(
        color: NoiseColor.white, volumePercent: 55, binauralOn: true, beatHz: 6));
    c.dispose();
  });

  test('the beat chip cycles 2, 4, 6, 8, 10 Hz', () {
    final c = make();
    final seen = <int>[];
    for (var i = 0; i < 5; i++) {
      c.nextBeat();
      seen.add(c.settings.beatHz);
    }
    expect(seen, [6, 8, 10, 2, 4]);
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

        // Headphones in: Android stopped the stream; it comes back.
        audio.running = false;
        audio.events |= PlayerEvent.rerouted;
        audio.calls.clear();
        async.elapse(tick);
        expect(audio.calls, ['open']);

        // Headphones out: paused first, so the speaker stays silent.
        c.routeLost();
        audio.running = false;
        audio.events |= PlayerEvent.rerouted;
        audio.calls.clear();
        async.elapse(tick);
        expect(audio.calls, isEmpty);

        // Play reopens the stream and resumes.
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

    test('another app taking over media ends the session', () {
      final c = make();
      c.playOrStop();
      c.focusLost(FocusLoss.permanent);
      expect(c.phase, SessionPhase.stopped);
      c.dispose();
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
