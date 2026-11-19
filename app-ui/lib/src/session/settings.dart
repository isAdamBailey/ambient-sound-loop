/// The last session's settings, saved per device as soon as each changes and
/// restored on launch, stopped. Spec #9 §6.
library;

import 'dart:math' as math;

import 'package:humspan_native/humspan_native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'length.dart';

/// Beat frequencies offered by the binaural chip, in Hz.
const beatFrequencies = <int>[2, 4, 6, 8, 10];

/// Seconds between boom strikes, slowest first.
const boomIntervals = <int>[8, 4, 2];

/// The three sound layers, each with its own On/Off and level.
enum SoundLayer { noise, binaural, boom }

@immutable
class SessionSettings {
  const SessionSettings({
    required this.noiseOn,
    required this.color,
    required this.length,
    required this.binauralOn,
    required this.beatHz,
    required this.boomOn,
    required this.boomSeconds,
    this.noiseLevel = 1,
    this.binauralLevel = 1,
    this.boomLevel = 1,
  });

  /// Noise on (Pink), 8 h, binaural off, boom off. The beat starts at 4 Hz
  /// and the boom at 8 s; every level slider at 100 %. Loudness is the
  /// device volume.
  static const firstLaunch = SessionSettings(
    noiseOn: true,
    color: NoiseColor.pink,
    length: TimedLength(Duration(hours: 8)),
    binauralOn: false,
    beatHz: 4,
    boomOn: false,
    boomSeconds: 8,
  );

  final bool noiseOn;
  final NoiseColor color;
  final SessionLength length;
  final bool binauralOn;
  final int beatHz; // one of [beatFrequencies]
  final bool boomOn;
  final int boomSeconds; // one of [boomIntervals]

  /// Level slider positions, 0–1 (not gains; see [levelGain]).
  final double noiseLevel;
  final double binauralLevel;
  final double boomLevel;

  /// At least one layer is switched on (a level of 0 still counts as on).
  bool get anyLayerOn => noiseOn || binauralOn || boomOn;

  bool isOn(SoundLayer layer) => switch (layer) {
    SoundLayer.noise => noiseOn,
    SoundLayer.binaural => binauralOn,
    SoundLayer.boom => boomOn,
  };

  double level(SoundLayer layer) => switch (layer) {
    SoundLayer.noise => noiseLevel,
    SoundLayer.binaural => binauralLevel,
    SoundLayer.boom => boomLevel,
  };

  SessionSettings withLevel(SoundLayer layer, double position) => switch (layer) {
    SoundLayer.noise => copyWith(noiseLevel: position),
    SoundLayer.binaural => copyWith(binauralLevel: position),
    SoundLayer.boom => copyWith(boomLevel: position),
  };

  SessionSettings copyWith({
    bool? noiseOn,
    NoiseColor? color,
    SessionLength? length,
    bool? binauralOn,
    int? beatHz,
    bool? boomOn,
    int? boomSeconds,
    double? noiseLevel,
    double? binauralLevel,
    double? boomLevel,
  }) => SessionSettings(
    noiseOn: noiseOn ?? this.noiseOn,
    color: color ?? this.color,
    length: length ?? this.length,
    binauralOn: binauralOn ?? this.binauralOn,
    beatHz: beatHz ?? this.beatHz,
    boomOn: boomOn ?? this.boomOn,
    boomSeconds: boomSeconds ?? this.boomSeconds,
    noiseLevel: noiseLevel ?? this.noiseLevel,
    binauralLevel: binauralLevel ?? this.binauralLevel,
    boomLevel: boomLevel ?? this.boomLevel,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionSettings &&
      other.noiseOn == noiseOn &&
      other.color == color &&
      other.length == length &&
      other.binauralOn == binauralOn &&
      other.beatHz == beatHz &&
      other.boomOn == boomOn &&
      other.boomSeconds == boomSeconds &&
      other.noiseLevel == noiseLevel &&
      other.binauralLevel == binauralLevel &&
      other.boomLevel == boomLevel;

  @override
  int get hashCode => Object.hash(
    noiseOn,
    color,
    length,
    binauralOn,
    beatHz,
    boomOn,
    boomSeconds,
    noiseLevel,
    binauralLevel,
    boomLevel,
  );

  @override
  String toString() =>
      'SessionSettings(noise ${noiseOn ? 'on' : 'off'} ${color.name} $noiseLevel, '
      '${length.tileText}, '
      'binaural ${binauralOn ? 'on' : 'off'} $beatHz Hz $binauralLevel, '
      'boom ${boomOn ? 'on' : 'off'} ${boomSeconds}s $boomLevel)';
}

/// The bottom of a level slider's dB taper: quiet, never silent. Only a
/// layer's toggle turns it off.
const levelFloorDb = -40.0;

/// Engine gain for a level slider at [position] (0–1): 100 % is 0 dB, the
/// steps are even in dB down to [levelFloorDb] at 0.
double levelGain(double position) {
  final p = position.clamp(0.0, 1.0);
  return math.pow(10, levelFloorDb * (1 - p) / 20).toDouble();
}

/// Reads and writes [SessionSettings] in the platform's preferences store.
/// Anything missing or out of range reads as its first-launch value, so an
/// upgrade from an install without a setting keeps all the others.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _noise = 'noiseOn';
  static const _color = 'color';
  static const _lengthSeconds = 'lengthSeconds'; // 0 = Until I stop
  static const _binaural = 'binauralOn';
  static const _beat = 'beatHz';
  static const _boom = 'boomOn';
  static const _boomSeconds = 'boomSeconds';
  static const _noiseLevel = 'noiseLevel';
  static const _binauralLevel = 'binauralLevel';
  static const _boomLevel = 'boomLevel';

  Future<SessionSettings> load() async {
    const d = SessionSettings.firstLaunch;
    final noise = await _prefs.getBool(_noise);
    final colorName = await _prefs.getString(_color);
    final seconds = await _prefs.getInt(_lengthSeconds);
    final binaural = await _prefs.getBool(_binaural);
    final beat = await _prefs.getInt(_beat);
    final boom = await _prefs.getBool(_boom);
    final boomSeconds = await _prefs.getInt(_boomSeconds);

    Future<double> level(String key, double fallback) async {
      final v = await _prefs.getDouble(key);
      return v != null && v >= 0 && v <= 1 ? v : fallback;
    }

    return SessionSettings(
      noiseOn: noise ?? d.noiseOn,
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
      noiseLevel: await level(_noiseLevel, d.noiseLevel),
      binauralLevel: await level(_binauralLevel, d.binauralLevel),
      boomLevel: await level(_boomLevel, d.boomLevel),
    );
  }

  Future<void> save(SessionSettings settings) async {
    await _prefs.setBool(_noise, settings.noiseOn);
    await _prefs.setString(_color, settings.color.name);
    await _prefs.setInt(_lengthSeconds, settings.length.duration?.inSeconds ?? 0);
    await _prefs.setBool(_binaural, settings.binauralOn);
    await _prefs.setInt(_beat, settings.beatHz);
    await _prefs.setBool(_boom, settings.boomOn);
    await _prefs.setInt(_boomSeconds, settings.boomSeconds);
    await _prefs.setDouble(_noiseLevel, settings.noiseLevel);
    await _prefs.setDouble(_binauralLevel, settings.binauralLevel);
    await _prefs.setDouble(_boomLevel, settings.boomLevel);
  }
}
