import 'dart:math' as math;

import 'package:humspan/src/session/length.dart';
import 'package:humspan/src/session/session_controller.dart';
import 'package:humspan/src/session/settings.dart';
import 'package:humspan/src/ui/controls.dart';
import 'package:humspan/src/ui/session_dial.dart';
import 'package:humspan/src/ui/session_screen.dart';
import 'package:humspan/src/ui/theme.dart';
import 'package:humspan_native/humspan_native.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_audio.dart';

void main() {
  late FakeAudio audio;
  late SessionController controller;
  late List<SessionSettings> saved;

  Future<void> pumpScreen(WidgetTester tester, Size size,
      {SessionSettings settings = SessionSettings.firstLaunch}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audio = FakeAudio();
    saved = [];
    controller = SessionController(
      audio: audio,
      settings: settings,
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: saved.add,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme: sessionTheme(), home: SessionScreen(controller: controller)));
  }

  Offset centerOf(WidgetTester tester, String text) => tester.getCenter(find.text(text).first);
  Finder playButtonFinder() => find.bySemanticsLabel('Play');
  Finder stopButtonFinder() => find.bySemanticsLabel('Stop');

  group('layout', () {
    testWidgets('under 900 px: dial, stops, layers, then Play, top to bottom', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final ys = ['8:00:00', '2h', 'NOISE', 'BINAURAL BEAT', 'BOOM'].map((t) => centerOf(tester, t).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
      expect(tester.getCenter(playButtonFinder()).dy, greaterThan(ys.last));
      expect(centerOf(tester, '8:00:00').dx, closeTo(195, 1));
      expect(tester.getBottomRight(playButtonFinder()).dy, lessThanOrEqualTo(844), reason: 'fits without scrolling');
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 900 px and up the dial sits left of the layers', (tester) async {
      await pumpScreen(tester, const Size(900, 640));
      expect(centerOf(tester, '8:00:00').dx, lessThan(centerOf(tester, 'NOISE').dx));
      final ys = ['NOISE', 'BINAURAL BEAT', 'BOOM'].map((t) => centerOf(tester, t).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
      expect(tester.getCenter(playButtonFinder()).dy, greaterThan(ys.last));
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches when the window is resized across 900 px', (tester) async {
      await pumpScreen(tester, const Size(1200, 700));
      expect(centerOf(tester, '8:00:00').dx, lessThan(centerOf(tester, 'NOISE').dx - 100));
      tester.view.physicalSize = const Size(899, 700);
      await tester.pump();
      expect(centerOf(tester, '8:00:00').dy, lessThan(centerOf(tester, 'NOISE').dy));
      expect(centerOf(tester, '8:00:00').dx, closeTo(449.5, 1));
    });

    testWidgets('the minimum desktop window and a landscape phone do not overflow', (tester) async {
      await pumpScreen(tester, const Size(360, 640));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('layers', () {
    testWidgets('noise colors select one and expose their pressed state', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(tester.getSemantics(find.text('Pink')), isSemantics(isButton: true, isToggled: true));
      await tester.tap(find.text('Brown'));
      await tester.pump();
      expect(controller.settings.color, NoiseColor.brown);
      expect(tester.getSemantics(find.text('Brown')), isSemantics(isButton: true, isToggled: true));
      expect(tester.getSemantics(find.text('Pink')), isSemantics(isButton: true, isToggled: false));
      semantics.dispose();
    });

    testWidgets('noise switches on its own; the colors stay usable while off', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(tester.getSemantics(find.bySemanticsLabel('Noise')), isSemantics(isButton: true, isToggled: true));
      await tester.tap(find.bySemanticsLabel('Noise'));
      await tester.pump();
      expect(controller.settings.noiseOn, isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Noise')), isSemantics(isButton: true, isToggled: false));
      await tester.tap(find.text('White'));
      await tester.pump();
      expect(controller.settings.color, NoiseColor.white);
      expect(controller.settings.noiseOn, isFalse);
      semantics.dispose();
    });

    testWidgets('an off layer keeps its height', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final before = centerOf(tester, 'BOOM').dy;
      await tester.tap(find.bySemanticsLabel('Noise'));
      await tester.pump();
      expect(centerOf(tester, 'BOOM').dy, before);
    });

    testWidgets('each layer has a labelled level slider that announces a percentage', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844),
          settings: SessionSettings.firstLaunch.copyWith(binauralLevel: 0.5));
      expect(find.byType(Slider), findsNWidgets(3));
      expect(tester.getSemantics(find.bySemanticsLabel('Noise level')),
          isSemantics(isSlider: true, value: '100%', isEnabled: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Binaural level')),
          isSemantics(isSlider: true, value: '50%', isEnabled: true),
          reason: 'usable while binaural is off');
      expect(tester.getSemantics(find.bySemanticsLabel('Boom level')),
          isSemantics(isSlider: true, value: '100%', isEnabled: true));
      expect(find.text('50%'), findsOneWidget, reason: 'the percentage is written beside the slider');
      semantics.dispose();
    });

    testWidgets('dragging a level slider moves only its layer and saves at the end', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final boom = find.byType(Slider).at(2);
      final width = tester.getSize(boom).width;
      await tester.drag(boom, Offset(-width / 2, 0));
      await tester.pump();
      expect(controller.settings.boomLevel, lessThan(0.9));
      expect(controller.settings.noiseLevel, 1.0);
      expect(controller.settings.binauralLevel, 1.0);
      expect(saved, hasLength(1), reason: 'one save, when the drag ended');
      expect(saved.single.boomLevel, controller.settings.boomLevel);
    });

    testWidgets('the beat stepper moves one frequency at a time and stops at the ends', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(tester.getSemantics(find.bySemanticsLabel('Binaural beat')),
          isSemantics(isButton: true, isToggled: false));
      await tester.tap(find.bySemanticsLabel('Binaural beat'));
      await tester.pump();
      expect(controller.settings.binauralOn, isTrue);
      await tester.tap(find.bySemanticsLabel('Raise beat frequency'));
      await tester.pump();
      expect(find.text('6 Hz'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.bySemanticsLabel('Raise beat frequency'));
        await tester.pump();
      }
      expect(controller.settings.beatHz, 10);
      expect(tester.getSemantics(find.bySemanticsLabel('Raise beat frequency')), isSemantics(isButton: true, isEnabled: false));
      await tester.tap(find.bySemanticsLabel('Lower beat frequency'));
      await tester.pump();
      expect(controller.settings.beatHz, 8);
      semantics.dispose();
    });

    testWidgets('boom switches without touching the beat; its gap is one of three', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(tester.getSemantics(find.bySemanticsLabel('Boom')), isSemantics(isButton: true, isToggled: false));
      expect(find.bySemanticsLabel('Boom, alternates left and right'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Boom'));
      await tester.pump();
      expect(controller.settings.boomOn, isTrue);
      expect(controller.settings.binauralOn, isFalse);
      await tester.tap(find.bySemanticsLabel('Boom every 4 seconds'));
      await tester.pump();
      expect(controller.settings.boomSeconds, 4);
      expect(tester.getSemantics(find.bySemanticsLabel('Boom every 4 seconds')),
          isSemantics(isButton: true, isToggled: true));
      semantics.dispose();
    });
  });

  group('mono', () {
    testWidgets('a Mono switch under the layers, stereo by default, saved when switched', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      final mono = find.bySemanticsLabel('Mono, same sound in both ears');
      expect(tester.getSemantics(mono), isSemantics(isButton: true, isToggled: false));
      expect(find.bySemanticsLabel('Mono'), findsNothing, reason: 'announced once, by the switch');
      expect(find.bySemanticsLabel('Same sound in both ears'), findsNothing);
      expect(centerOf(tester, 'Mono').dy, greaterThan(centerOf(tester, 'BOOM').dy));
      expect(centerOf(tester, 'Mono').dy, lessThan(tester.getCenter(playButtonFinder()).dy));
      await tester.tap(mono);
      await tester.pump();
      expect(controller.settings.mono, isTrue);
      expect(audio.calls.last, 'mono true');
      expect(saved.last.mono, isTrue);
      expect(tester.getSemantics(mono), isSemantics(isButton: true, isToggled: true));
      // Every strike reaches both ears, so the boom no longer claims left and right.
      expect(find.bySemanticsLabel('Boom, alternates left and right'), findsNothing);
      expect(find.text('left'), findsNothing);
      semantics.dispose();
    });
  });

  group('play', () {
    testWidgets('with every layer off Play is disabled, with a note', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      expect(find.text('Turn on a sound to play.'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Noise'));
      await tester.pump();
      expect(find.text('Turn on a sound to play.'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
      await tester.tap(playButtonFinder(), warnIfMissed: false);
      await tester.pump();
      expect(controller.phase, SessionPhase.stopped);

      await tester.tap(find.bySemanticsLabel('Boom'));
      await tester.pump();
      await tester.tap(playButtonFinder());
      await tester.pump();
      expect(controller.phase, SessionPhase.playing);

      // While playing, the last layer can still be switched off. (The note
      // under Play also reads "Boom", so find the switch itself.)
      await tester.tap(find.byWidgetPredicate((w) => w is LayerSwitch && w.label == 'Boom'));
      await tester.pump();
      expect(controller.settings.boomOn, isFalse);
      expect(controller.phase, SessionPhase.playing);
      expect(find.text('Turn on a sound to play.'), findsNothing);
      expect(stopButtonFinder(), findsOneWidget);
    });

    testWidgets('the note under Play says what will play and for how long', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      expect(find.text('Pink noise\nfor 8 h, then fades out'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Until I stop'));
      await tester.pump();
      expect(find.text('Pink noise\nuntil you stop'), findsOneWidget);
    });

    testWidgets('headphones out: amber status in place of the stops, dimmed clock, Play shown', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await tester.tap(playButtonFinder());
      await tester.pump();
      controller.routeLost();
      await tester.pump();
      final status = tester.widget<Text>(find.text('Headphones disconnected. Paused.'));
      expect(status.style?.color, SessionColors.state);
      expect(find.text('2h'), findsNothing);
      expect(playButtonFinder(), findsOneWidget);
      final clock = tester.widget<Text>(find.text('8:00:00'));
      expect(clock.style?.color, SessionColors.dim);
    });
  });

  group('dial', () {
    testWidgets('a preset stop sets the length and shows when it ends', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(find.textContaining('ends', findRichText: true), findsOneWidget);
      await tester.tap(find.text('2h'));
      await tester.pump();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 2)));
      expect(find.text('2:00:00'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('2 h')), isSemantics(isButton: true, isToggled: true, isEnabled: true));
      await tester.tap(find.bySemanticsLabel('Until I stop'));
      await tester.pump();
      expect(controller.settings.length, SessionLength.untilStop);
      expect(find.text('0:00:00'), findsOneWidget);
      expect(find.text('until you stop'), findsOneWidget);
      expect(find.textContaining('ends', findRichText: true), findsNothing, reason: 'no end to show');
      semantics.dispose();
    });

    testWidgets('dragging round the ring sets the length in 5-minute steps and saves once', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final dial = find.byType(SessionDial);
      final center = tester.getCenter(dial);
      final r = tester.getSize(dial).width / 2 - 14;
      // A quarter turn clockwise, from 12 to 3: three hours more.
      final gesture = await tester.startGesture(center + Offset(0, -r));
      for (var i = 1; i <= 12; i++) {
        final a = -1.5708 + i / 12 * 1.5708;
        await gesture.moveTo(center + Offset(r * math.cos(a), r * math.sin(a)));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      final seconds = controller.settings.length.duration!.inSeconds;
      expect(seconds % 300, 0);
      expect(seconds, inInclusiveRange(10 * 3600 + 30 * 60, 11 * 3600));
      expect(saved, hasLength(1), reason: 'saved when the drag ended, not on every step');
    });

    testWidgets('Until I stop survives a drag across the center and has no nudges', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844),
          settings: SessionSettings.firstLaunch.copyWith(length: SessionLength.untilStop));
      final center = tester.getCenter(find.byType(SessionDial));
      await tester.dragFrom(center + const Offset(-30, 0), const Offset(60, 40));
      await tester.pump();
      expect(controller.settings.length, SessionLength.untilStop);
      final node = tester.getSemantics(find.bySemanticsLabel('Session length'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isFalse);
      semantics.dispose();
    });

    testWidgets('the dial is a slider for assistive technology', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      final node = tester.getSemantics(find.bySemanticsLabel('Session length'));
      expect(node, isSemantics(isSlider: true, value: '8 h'));
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8, minutes: 15)));
      semantics.dispose();
    });

    testWidgets('locked while a session runs; the stops cannot change it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      await tester.tap(playButtonFinder());
      await tester.pump();
      expect(find.text('Length applies next session.'), findsNothing);
      expect(find.text('Exact'), findsNothing);
      expect(find.bySemanticsLabel('Session length'), findsNothing);
      expect(tester.getSemantics(find.bySemanticsLabel('2 h')), isSemantics(isButton: true, isEnabled: false));
      await tester.tap(find.text('2h'), warnIfMissed: false);
      await tester.pump();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8)));
      await tester.tap(stopButtonFinder());
      await tester.pump();
      expect(controller.phase, SessionPhase.stopped);
      expect(find.text('Exact'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('past 12 hours the clock shows the whole length', (tester) async {
      await pumpScreen(tester, const Size(390, 844),
          settings: SessionSettings.firstLaunch.copyWith(length: SessionLength.timed(const Duration(hours: 36))));
      expect(find.text('36:00:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('exact entry', () {
    Future<void> openExact(WidgetTester tester) async {
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      expect(find.text('Session length'), findsOneWidget);
    }

    testWidgets('narrow uses a keypad in a bottom sheet; Done applies', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openExact(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final key in ['1', '3', '7', '0', '0']) {
        await tester.tap(find.widgetWithText(TextButton, key).last);
        await tester.pump();
      }
      expect(find.text('01h 37m 00s'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 1, minutes: 37)));
      expect(find.text('1:37:00'), findsOneWidget);
    });

    testWidgets('Cancel discards', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openExact(tester);
      await tester.tap(find.widgetWithText(TextButton, '5').last);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8)));
    });

    testWidgets('a zero length is refused with a message', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openExact(tester);
      // From a preset, exact entry starts empty; backspace on empty does nothing.
      await tester.tap(find.bySemanticsLabel('Delete last digit'));
      await tester.pump();
      expect(find.text('Enter a length, or choose Until I stop.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Session length'), findsOneWidget, reason: 'still open');
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8)));
    });

    testWidgets('wide opens a dialog with typed fields and a total', (tester) async {
      await pumpScreen(tester, const Size(1280, 720));
      await openExact(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Hours'), '1');
      await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '37');
      await tester.enterText(find.widgetWithText(TextField, 'Seconds'), '0');
      await tester.pump();
      expect(find.text('= 1h 37m'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 1, minutes: 37)));
    });

    testWidgets('a custom length reopens with its digits', (tester) async {
      await pumpScreen(tester, const Size(390, 844),
          settings: SessionSettings.firstLaunch.copyWith(
              length: SessionLength.timed(const Duration(hours: 1, minutes: 37))));
      await openExact(tester);
      expect(find.text('01h 37m 00s'), findsOneWidget);
    });
  });

  group('accessibility and copy', () {
    testWidgets('touch targets are at least 44 px', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(360, 640));
      for (final label in [
        'Noise', 'Binaural beat', 'Boom', 'Raise beat frequency', 'Lower beat frequency',
        'Boom every 8 seconds', 'Until I stop', '30 min', 'Play',
      ]) {
        final size = tester.getSize(find.bySemanticsLabel(label).first);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      for (final word in ['White', 'Pink', 'Brown', 'Exact']) {
        final size = tester.getSemantics(find.text(word)).rect.size;
        expect(size.height, greaterThanOrEqualTo(44), reason: word);
        expect(size.width, greaterThanOrEqualTo(44), reason: word);
      }
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(find.byType(Slider).at(i)).height, greaterThanOrEqualTo(44), reason: 'slider $i');
      }
      semantics.dispose();
    });

    testWidgets('no sleep, health or entrainment wording', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final words = RegExp(r'sleep|health|brain|entrain|focus|relax|calm|anxi', caseSensitive: false);
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' ');
      expect(words.hasMatch(texts), isFalse, reason: texts);
    });
  });
}

