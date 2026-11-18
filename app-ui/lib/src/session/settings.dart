/// The last session's settings, saved per device as soon as each changes and
/// restored on launch, stopped. Spec #9 §6.
library;

import 'package:ambient_native/ambient_native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'length.dart';

/// Beat frequencies offered by the binaural chip, in Hz.
const beatFrequencies = <int>[2, 4, 6, 8, 10];

/// Seconds between boom strikes, slowest first.
const boomIntervals = <int>[8, 4, 2];

@immutable
class SessionSettings {
  const SessionSettings({
    required this.color,
    required this.length,
    required this.binauralOn,
    required this.beatHz,
    required this.boomOn,
    required this.boomSeconds,
  });

  /// Pink, 8 h, binaural off, boom off. The beat starts at 4 Hz and the boom
  /// at 8 s. Loudness is the device volume.
  static const firstLaunch = SessionSettings(
    color: NoiseColor.pink,
    length: TimedLength(Duration(hours: 8)),
    binauralOn: false,
    beatHz: 4,
    boomOn: false,
    boomSeconds: 8,
  );

  final NoiseColor color;
  final SessionLength length;
  final bool binauralOn;
  final int beatHz; // one of [beatFrequencies]
  final bool boomOn;
  final int boomSeconds; // one of [boomIntervals]

  SessionSettings copyWith({
    NoiseColor? color,
    SessionLength? length,
    bool? binauralOn,
    int? beatHz,
    bool? boomOn,
    int? boomSeconds,
  }) => SessionSettings(
    color: color ?? this.color,
    length: length ?? this.length,
    binauralOn: binauralOn ?? this.binauralOn,
    beatHz: beatHz ?? this.beatHz,
    boomOn: boomOn ?? this.boomOn,
    boomSeconds: boomSeconds ?? this.boomSeconds,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionSettings &&
      other.color == color &&
      other.length == length &&
      other.binauralOn == binauralOn &&
      other.beatHz == beatHz &&
      other.boomOn == boomOn &&
      other.boomSeconds == boomSeconds;

  @override
  int get hashCode => Object.hash(color, length, binauralOn, beatHz, boomOn, boomSeconds);

  @override
  String toString() =>
      'SessionSettings(${color.name}, ${length.tileText}, '
      'binaural ${binauralOn ? 'on' : 'off'} $beatHz Hz, '
      'boom ${boomOn ? 'on' : 'off'} ${boomSeconds}s)';
}

/// Reads and writes [SessionSettings] in the platform's preferences store.
/// Anything missing or out of range reads as its first-launch value.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _color = 'color';
  static const _lengthSeconds = 'lengthSeconds'; // 0 = Until I stop
  static const _binaural = 'binauralOn';
  static const _beat = 'beatHz';
  static const _boom = 'boomOn';
  static const _boomSeconds = 'boomSeconds';

  Future<SessionSettings> load() async {
    const d = SessionSettings.firstLaunch;
    final colorName = await _prefs.getString(_color);
    final seconds = await _prefs.getInt(_lengthSeconds);
    final binaural = await _prefs.getBool(_binaural);
    final beat = await _prefs.getInt(_beat);
    final boom = await _prefs.getBool(_boom);
    final boomSeconds = await _prefs.getInt(_boomSeconds);

    return SessionSettings(
      color: NoiseColor.values.where((c) => c.name == colorName).firstOrNull ?? d.color,
      length: switch (seconds) {
        0 => SessionLength.untilStop,
        final int s when s > 0 => SessionLength.timed(Duration(seconds: s)),
        _ => d.length,
      },
      binauralOn: binaural ?? d.binauralOn,
      beatHz: beatFrequencies.contains(beat) ? beat! : d.beatHz,
      boomOn: boom ?? d.boomOn,
      boomSeconds: boomIntervals.contains(boomSeconds) ? boomSeconds! : d.boomSeconds,
    );
  }

  Future<void> save(SessionSettings settings) async {
    await _prefs.setString(_color, settings.color.name);
    await _prefs.setInt(_lengthSeconds, settings.length.duration?.inSeconds ?? 0);
    await _prefs.setBool(_binaural, settings.binauralOn);
    await _prefs.setInt(_beat, settings.beatHz);
    await _prefs.setBool(_boom, settings.boomOn);
    await _prefs.setInt(_boomSeconds, settings.boomSeconds);
  }
}
