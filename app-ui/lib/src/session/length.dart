/// Session length: a timed length or Until I stop, the dial's preset stops,
/// and exact entry by keypad (narrow) or fields (wide). Spec #9 §4.
library;

import 'package:flutter/foundation.dart';

/// The length chosen for the next session.
@immutable
sealed class SessionLength {
  const SessionLength();

  factory SessionLength.timed(Duration duration) = TimedLength;

  /// A session with no set duration. Its clock shows elapsed time.
  static const SessionLength untilStop = UntilStop();

  /// The length in short form, as the Length tile shows it.
  String get tileText;

  /// The duration, or null for Until I stop.
  Duration? get duration;
}

final class TimedLength extends SessionLength {
  const TimedLength(this.value);
  final Duration value;

  @override
  Duration get duration => value;

  @override
  String get tileText {
    final total = value.inSeconds;
    final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
    if (h == 0 && m == 0) return '$s s';
    if (h == 0) return s == 0 ? '$m min' : '${m}m ${s}s';
    if (m == 0 && s == 0) return '$h h';
    return s == 0 ? '${h}h ${m}m' : '${h}h ${m}m ${s}s';
  }

  @override
  bool operator ==(Object other) => other is TimedLength && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class UntilStop extends SessionLength {
  const UntilStop();

  @override
  Duration? get duration => null;

  @override
  String get tileText => 'Until I stop';

  @override
  bool operator ==(Object other) => other is UntilStop;

  @override
  int get hashCode => 0;
}

/// The longest session the dial or exact entry can set.
const maxSessionLength = Duration(hours: 99, minutes: 59, seconds: 59);

/// A preset stop under the length dial.
@immutable
class LengthPreset {
  const LengthPreset(this.label, this.length);
  final String label;
  final SessionLength length;
}

const lengthPresets = <LengthPreset>[
  LengthPreset('30m', TimedLength(Duration(minutes: 30))),
  LengthPreset('1h', TimedLength(Duration(hours: 1))),
  LengthPreset('2h', TimedLength(Duration(hours: 2))),
  LengthPreset('4h', TimedLength(Duration(hours: 4))),
  LengthPreset('8h', TimedLength(Duration(hours: 8))),
  LengthPreset('Until I stop', UntilStop()),
];

/// An exact length being typed: up to six digits, HHMMSS, filled from the
/// right like a phone timer. Minutes and seconds above 59 show as typed but
/// count as 59.
@immutable
class ExactEntry {
  const ExactEntry.empty() : _digits = '';

  const ExactEntry._(this._digits);

  /// Entry that starts from [duration] (hours capped at 99).
  factory ExactEntry.of(Duration duration) {
    final total = duration.inSeconds;
    final h = (total ~/ 3600).clamp(0, 99);
    return const ExactEntry.empty()
        .withFields(hours: h, minutes: (total % 3600) ~/ 60, seconds: total % 60);
  }

  static const _maxDigits = 6;

  final String _digits; // no leading zeros

  String get _padded => _digits.padLeft(_maxDigits, '0');

  int get hours => int.parse(_padded.substring(0, 2));
  int get minutes => int.parse(_padded.substring(2, 4));
  int get seconds => int.parse(_padded.substring(4, 6));

  /// The keypad readout, e.g. `01h 37m 00s`.
  String get readout =>
      '${_padded.substring(0, 2)}h ${_padded.substring(2, 4)}m ${_padded.substring(4, 6)}s';

  /// The length entered, with minutes and seconds clamped to 59.
  Duration get duration =>
      Duration(hours: hours, minutes: minutes.clamp(0, 59), seconds: seconds.clamp(0, 59));

  /// A zero length is refused.
  bool get isValid => duration > Duration.zero;

  /// Keypad: a digit `0`–`9`, or `00`.
  ExactEntry press(String key) {
    assert(RegExp(r'^(\d|00)$').hasMatch(key), 'not a keypad key: $key');
    var digits = (_digits + key).replaceFirst(RegExp('^0+'), '');
    if (digits.length > _maxDigits) digits = digits.substring(0, _maxDigits);
    return ExactEntry._(digits);
  }

  /// Keypad: remove the last digit.
  ExactEntry backspace() =>
      _digits.isEmpty ? this : ExactEntry._(_digits.substring(0, _digits.length - 1));

  /// Wide layout: typed Hours / Minutes / Seconds fields (0–99 each).
  ExactEntry withFields({int? hours, int? minutes, int? seconds}) {
    String two(int v) => v.clamp(0, 99).toString().padLeft(2, '0');
    final digits = two(hours ?? this.hours) + two(minutes ?? this.minutes) + two(seconds ?? this.seconds);
    return ExactEntry._(digits.replaceFirst(RegExp('^0+'), ''));
  }

  @override
  bool operator ==(Object other) => other is ExactEntry && other._digits == _digits;

  @override
  int get hashCode => _digits.hashCode;
}
