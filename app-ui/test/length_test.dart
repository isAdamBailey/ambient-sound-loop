import 'package:ambient_app/src/session/length.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tile text', () {
    test('matches the spec examples', () {
      expect(SessionLength.timed(const Duration(hours: 1, minutes: 30)).tileText, '1h 30m');
      expect(SessionLength.timed(const Duration(hours: 8)).tileText, '8 h');
      expect(SessionLength.timed(const Duration(hours: 1, minutes: 37)).tileText, '1h 37m');
      expect(SessionLength.untilStop.tileText, 'Until I stop');
    });

    test('short and odd lengths', () {
      expect(SessionLength.timed(const Duration(minutes: 30)).tileText, '30 min');
      expect(SessionLength.timed(const Duration(seconds: 45)).tileText, '45 s');
      expect(SessionLength.timed(const Duration(minutes: 2, seconds: 5)).tileText, '2m 5s');
      expect(SessionLength.timed(const Duration(hours: 1, seconds: 9)).tileText, '1h 0m 9s');
    });
  });

  test('presets are the spec list, in order', () {
    expect(lengthPresets.map((p) => p.label), [
      '30 min', '1 h', '1h 30m', '2 h', '8 h', 'Until I stop',
    ]);
    expect(lengthPresets[2].length, SessionLength.timed(const Duration(minutes: 90)));
    expect(lengthPresets.last.length, SessionLength.untilStop);
  });

  group('keypad entry', () {
    test('digits fill from the right like a phone timer', () {
      var entry = const ExactEntry.empty();
      for (final key in ['1', '3', '7', '0', '0']) {
        entry = entry.press(key);
      }
      expect(entry.readout, '01h 37m 00s');
      expect(entry.duration, const Duration(hours: 1, minutes: 37));
    });

    test('00 adds two digits and backspace removes the last', () {
      final entry = const ExactEntry.empty().press('5').press('00');
      expect(entry.readout, '00h 05m 00s');
      expect(entry.backspace().readout, '00h 00m 50s');
    });

    test('leading zeros are ignored and entry stops at six digits', () {
      var entry = const ExactEntry.empty().press('0').press('00');
      expect(entry.readout, '00h 00m 00s');
      for (final key in ['1', '2', '3', '4', '5', '6', '7']) {
        entry = entry.press(key);
      }
      expect(entry.readout, '12h 34m 56s');
    });

    test('minutes and seconds above 59 clamp to 59', () {
      var entry = const ExactEntry.empty();
      for (final key in ['9', '9', '9', '9']) {
        entry = entry.press(key);
      }
      expect(entry.duration, const Duration(minutes: 59, seconds: 59));
    });

    test('starts from an existing length', () {
      final entry = ExactEntry.of(const Duration(hours: 1, minutes: 37));
      expect(entry.readout, '01h 37m 00s');
      expect(entry.press('5').readout, '13h 70m 05s');
    });
  });

  group('field entry', () {
    test('hours, minutes and seconds with clamping', () {
      final entry = const ExactEntry.empty().withFields(hours: 2, minutes: 75, seconds: 30);
      expect(entry.duration, const Duration(hours: 2, minutes: 59, seconds: 30));
      expect(entry.hours, 2);
      expect(entry.minutes, 75);
    });
  });

  test('a zero exact length is refused', () {
    expect(const ExactEntry.empty().isValid, isFalse);
    expect(const ExactEntry.empty().press('1').isValid, isTrue);
  });
}
