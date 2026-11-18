import 'package:ambient_app/src/session/length.dart';
import 'package:ambient_app/src/session/session_controller.dart';
import 'package:ambient_app/src/session/settings.dart';
import 'package:ambient_app/src/ui/session_screen.dart';
import 'package:ambient_app/src/ui/theme.dart';
import 'package:ambient_native/ambient_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_audio.dart';

void main() {
  late FakeAudio audio;
  late SessionController controller;

  Future<void> pumpScreen(WidgetTester tester, Size size,
      {SessionSettings settings = SessionSettings.firstLaunch}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audio = FakeAudio();
    controller = SessionController(
      audio: audio,
      settings: settings,
      reroute: RerouteBehavior.ignore,
      onSettingsChanged: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme: sessionTheme(), home: SessionScreen(controller: controller)));
  }

  Offset centerOf(WidgetTester tester, String text) => tester.getCenter(find.text(text).first);
  Finder playButtonFinder() => find.bySemanticsLabel('Play');
  Finder stopButtonFinder() => find.bySemanticsLabel('Stop');

  group('layout', () {
    testWidgets('under 900 px the blocks stack top to bottom', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final ys = ['8:00:00', 'COLOR', 'VOLUME', 'BINAURAL BEAT', 'LENGTH']
          .map((t) => centerOf(tester, t).dy)
          .toList();
      expect(ys, orderedEquals([...ys]..sort()));
      expect(tester.getCenter(playButtonFinder()).dy, greaterThan(ys.last));
      expect(tester.getCenter(playButtonFinder()).dx, closeTo(195, 1));
      expect(centerOf(tester, '8:00:00').dx, closeTo(195, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 900 px and up the same blocks sit in one row, left to right', (tester) async {
      await pumpScreen(tester, const Size(900, 640));
      final xs = ['8:00:00', 'COLOR', 'VOLUME', 'BINAURAL BEAT', 'LENGTH']
          .map((t) => centerOf(tester, t).dx)
          .toList();
      expect(xs, orderedEquals([...xs]..sort()));
      expect(tester.getCenter(playButtonFinder()).dx, greaterThan(xs.last));
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches when the window is resized across 900 px', (tester) async {
      await pumpScreen(tester, const Size(1200, 700));
      expect(centerOf(tester, 'COLOR').dx, lessThan(centerOf(tester, 'VOLUME').dx));
      expect(centerOf(tester, 'COLOR').dy, closeTo(centerOf(tester, 'VOLUME').dy, 40));
      tester.view.physicalSize = const Size(899, 700);
      await tester.pump();
      expect(centerOf(tester, 'COLOR').dy, lessThan(centerOf(tester, 'VOLUME').dy));
    });

    testWidgets('the minimum desktop window and a landscape phone do not overflow', (tester) async {
      await pumpScreen(tester, const Size(360, 640));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('controls', () {
    testWidgets('color buttons select one and expose their pressed state', (tester) async {
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

    testWidgets('volume is a labelled slider with a % readout', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(find.text('30%'), findsOneWidget);
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
      expect(tester.getSemantics(find.byType(Slider)), isSemantics(isSlider: true, value: '30%'));
      await tester.drag(find.byType(Slider), const Offset(400, 0));
      await tester.pump();
      expect(controller.settings.volumePercent, 100);
      expect(find.text('100%'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('binaural toggle and beat chip', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, const Size(390, 844));
      expect(find.text('Best with headphones'), findsOneWidget);
      expect(tester.getSemantics(find.text('Off')), isSemantics(isButton: true, isToggled: false));
      await tester.tap(find.text('Off'));
      await tester.pump();
      expect(controller.settings.binauralOn, isTrue);
      expect(tester.getSemantics(find.text('On')), isSemantics(isButton: true, isToggled: true));
      await tester.tap(find.text('4 Hz'));
      await tester.pump();
      expect(find.text('6 Hz'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Play and Stop, with the length note only while playing', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      expect(find.text('Length applies next session.'), findsNothing);
      await tester.tap(playButtonFinder());
      await tester.pump();
      expect(controller.phase, SessionPhase.playing);
      expect(stopButtonFinder(), findsOneWidget);
      expect(find.text('Length applies next session.'), findsOneWidget);
      await tester.tap(stopButtonFinder());
      await tester.pump();
      expect(controller.phase, SessionPhase.stopped);
      expect(playButtonFinder(), findsOneWidget);
    });

    testWidgets('headphones out: status pill, dimmed clock, Play shown', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await tester.tap(playButtonFinder());
      await tester.pump();
      controller.routeLost();
      await tester.pump();
      expect(find.text('Headphones disconnected. Paused.'), findsOneWidget);
      expect(playButtonFinder(), findsOneWidget);
      final clock = tester.widget<Text>(find.text('8:00:00'));
      expect(clock.style?.color, SessionColors.secondary);
    });

    testWidgets('touch targets are at least 44 px', (tester) async {
      await pumpScreen(tester, const Size(360, 640));
      for (final label in ['White', 'Pink', 'Brown', 'Off', '4 Hz']) {
        final size = tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(TextButton)).first);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      expect(tester.getSize(playButtonFinder()).height, greaterThanOrEqualTo(44));
    });

    testWidgets('no sleep, health or entrainment wording', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      final words = RegExp(r'sleep|health|brain|entrain|focus|relax|calm|anxi', caseSensitive: false);
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
      expect(words.hasMatch(texts), isFalse, reason: texts);
    });
  });

  group('length picker', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('LENGTH'));
      await tester.pumpAndSettle();
      expect(find.text('Session length'), findsOneWidget);
    }

    testWidgets('narrow opens a bottom sheet; Cancel discards', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openPicker(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('2 h'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8)));
      expect(find.text('8 h'), findsOneWidget);
    });

    testWidgets('a preset applies on Done', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openPicker(tester);
      await tester.tap(find.text('Until I stop'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.untilStop);
      expect(find.text('Until I stop'), findsOneWidget); // the tile
      expect(find.text('0:00:00'), findsOneWidget);
    });

    testWidgets('narrow exact entry uses the keypad', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openPicker(tester);
      await tester.tap(find.text('Exact…'));
      await tester.pump();
      for (final key in ['1', '3', '7', '0', '0']) {
        await tester.tap(find.widgetWithText(TextButton, key).last);
        await tester.pump();
      }
      expect(find.text('01h 37m 00s'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1h 37m'), findsOneWidget);
      expect(find.text('1:37:00'), findsOneWidget);
    });

    testWidgets('a zero length is refused with a message', (tester) async {
      await pumpScreen(tester, const Size(390, 844));
      await openPicker(tester);
      await tester.tap(find.text('Exact…'));
      await tester.pump();
      // Exact entry starts empty; backspace on empty does nothing.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.bySemanticsLabel('Delete last digit'));
        await tester.pump();
      }
      expect(find.text('Enter a length, or choose Until I stop.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Session length'), findsOneWidget, reason: 'still open');
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 8)));
    });

    testWidgets('wide opens a dialog with typed fields and a total', (tester) async {
      await pumpScreen(tester, const Size(1280, 720));
      await openPicker(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Exact…'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Hours'), '1');
      await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '37');
      await tester.enterText(find.widgetWithText(TextField, 'Seconds'), '0');
      await tester.pump();
      expect(find.text('= 1h 37m'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.settings.length, SessionLength.timed(const Duration(hours: 1, minutes: 37)));
    });

    testWidgets('a custom length reopens in exact entry', (tester) async {
      await pumpScreen(tester, const Size(390, 844),
          settings: SessionSettings.firstLaunch.copyWith(
              length: SessionLength.timed(const Duration(hours: 1, minutes: 37))));
      await openPicker(tester);
      expect(find.text('01h 37m 00s'), findsOneWidget);
    });
  });
}
