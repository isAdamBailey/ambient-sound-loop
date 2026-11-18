/// The last session's settings, saved per device as soon as each changes and
/// restored on launch, stopped. Spec #9 §6.
library;

import 'package:ambient_native/ambient_native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'length.dart';

/// Beat frequencies offered by the binaural chip, in Hz.
const beatFrequencies = <int>[2, 4, 6, 8, 10];

@immutable
class SessionSettings {
  const SessionSettings({
    required this.color,
    required this.volumePercent,
    required this.length,
    required this.binauralOn,
    required this.beatHz,
  });

  /// Pink, 30% volume, 8 h, binaural off; the beat starts at 4 Hz.
  static const firstLaunch = SessionSettings(
    color: NoiseColor.pink,
    volumePercent: 30,
    length: TimedLength(Duration(hours: 8)),
    binauralOn: false,
    beatHz: 4,
  );

  final NoiseColor color;
  final int volumePercent; // 0–100
  final SessionLength length;
  final bool binauralOn;
  final int beatHz; // one of [beatFrequencies]

  SessionSettings copyWith({
    NoiseColor? color,
    int? volumePercent,
    SessionLength? length,
    bool? binauralOn,
    int? beatHz,
  }) => SessionSettings(
    color: color ?? this.color,
    volumePercent: volumePercent ?? this.volumePercent,
    length: length ?? this.length,
    binauralOn: binauralOn ?? this.binauralOn,
    beatHz: beatHz ?? this.beatHz,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionSettings &&
      other.color == color &&
      other.volumePercent == volumePercent &&
      other.length == length &&
      other.binauralOn == binauralOn &&
      other.beatHz == beatHz;

  @override
  int get hashCode => Object.hash(color, volumePercent, length, binauralOn, beatHz);

  @override
  String toString() =>
      'SessionSettings(${color.name}, $volumePercent%, ${length.tileText}, '
      'binaural ${binauralOn ? 'on' : 'off'} $beatHz Hz)';
}

/// Reads and writes [SessionSettings] in the platform's preferences store.
/// Anything missing or out of range reads as its first-launch value.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _color = 'color';
  static const _volume = 'volume';
  static const _lengthSeconds = 'lengthSeconds'; // 0 = Until I stop
  static const _binaural = 'binauralOn';
  static const _beat = 'beatHz';

  Future<SessionSettings> load() async {
    const d = SessionSettings.firstLaunch;
    final colorName = await _prefs.getString(_color);
    final volume = await _prefs.getInt(_volume);
    final seconds = await _prefs.getInt(_lengthSeconds);
    final binaural = await _prefs.getBool(_binaural);
    final beat = await _prefs.getInt(_beat);

    return SessionSettings(
      color: NoiseColor.values.where((c) => c.name == colorName).firstOrNull ?? d.color,
      volumePercent: volume != null && volume >= 0 && volume <= 100 ? volume : d.volumePercent,
      length: switch (seconds) {
        0 => SessionLength.untilStop,
        final int s when s > 0 => SessionLength.timed(Duration(seconds: s)),
        _ => d.length,
      },
      binauralOn: binaural ?? d.binauralOn,
      beatHz: beatFrequencies.contains(beat) ? beat! : d.beatHz,
    );
  }

  Future<void> save(SessionSettings settings) async {
    await _prefs.setString(_color, settings.color.name);
    await _prefs.setInt(_volume, settings.volumePercent);
    await _prefs.setInt(_lengthSeconds, settings.length.duration?.inSeconds ?? 0);
    await _prefs.setBool(_binaural, settings.binauralOn);
    await _prefs.setInt(_beat, settings.beatHz);
  }
}
