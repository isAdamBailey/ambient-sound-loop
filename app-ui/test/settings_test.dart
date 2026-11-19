import 'dart:math' as math;

import 'package:humspan/src/session/length.dart';
import 'package:humspan/src/session/settings.dart';
import 'package:humspan_native/humspan_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('first launch: noise on (Pink), 8 h, binaural off at 4 Hz, levels at 100 %', () async {
    final settings = await SettingsStore(SharedPreferencesAsync()).load();
    expect(settings.noiseOn, isTrue);
    expect(settings.noiseLevel, 1.0);
    expect(settings.binauralLevel, 1.0);
    expect(settings.boomLevel, 1.0);
    expect(settings.color, NoiseColor.pink);
    expect(settings.length, SessionLength.timed(const Duration(hours: 8)));
    expect(settings.binauralOn, isFalse);
    expect(settings.beatHz, 4);
    expect(settings.boomOn, isFalse);
    expect(settings.boomSeconds, 8);
  });

  test('every setting round-trips through a new store', () async {
    const saved = SessionSettings(
      noiseOn: false,
      color: NoiseColor.brown,
      length: TimedLength(Duration(hours: 1, minutes: 37, seconds: 15)),
      binauralOn: true,
      beatHz: 10,
      boomOn: true,
      boomSeconds: 2,
      noiseLevel: 0.25,
      binauralLevel: 0.5,
      boomLevel: 0,
    );
    await SettingsStore(SharedPreferencesAsync()).save(saved);
    expect(await SettingsStore(SharedPreferencesAsync()).load(), saved);
  });

  test('Until I stop round-trips', () async {
    final saved = SessionSettings.firstLaunch.copyWith(length: SessionLength.untilStop);
    await SettingsStore(SharedPreferencesAsync()).save(saved);
    final loaded = await SettingsStore(SharedPreferencesAsync()).load();
    expect(loaded.length, SessionLength.untilStop);
  });

  test('values out of range fall back to first-launch settings', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('color', 'teal');
    await prefs.setInt('lengthSeconds', -5);
    await prefs.setInt('beatHz', 7);
    await prefs.setInt('boomSeconds', 3);
    await prefs.setDouble('noiseLevel', 1.5);
    await prefs.setDouble('binauralLevel', -0.1);
    final loaded = await SettingsStore(prefs).load();
    expect(loaded, SessionSettings.firstLaunch);
  });

  test('an install from before the layer toggles and levels keeps its settings', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('color', 'brown');
    await prefs.setInt('lengthSeconds', 3600);
    await prefs.setBool('binauralOn', true);
    await prefs.setInt('beatHz', 10);
    await prefs.setBool('boomOn', true);
    await prefs.setInt('boomSeconds', 2);
    final loaded = await SettingsStore(prefs).load();
    expect(loaded, SessionSettings.firstLaunch.copyWith(
        color: NoiseColor.brown,
        length: SessionLength.timed(const Duration(hours: 1)),
        binauralOn: true,
        beatHz: 10,
        boomOn: true,
        boomSeconds: 2));
    expect(loaded.noiseOn, isTrue);
    expect(loaded.noiseLevel, 1.0);
  });

  group('level taper', () {
    test('100 % is 0 dB and the bottom is -40 dB, never silence', () {
      expect(levelGain(1), 1.0);
      expect(levelGain(0), closeTo(0.01, 1e-12));
      expect(levelGain(-1), closeTo(0.01, 1e-12));
    });

    test('even dB steps down to -40 dB', () {
      double db(double p) => 20 * math.log(levelGain(p)) / math.ln10;
      expect(db(0.5), closeTo(-20, 1e-9));
      expect(db(0.75), closeTo(-10, 1e-9));
      expect(db(0.01), closeTo(-39.6, 1e-9));
      expect(db(0), closeTo(-40, 1e-9));
    });

    test('never raises a layer above its reference level', () {
      expect(levelGain(1.5), 1.0);
      for (var p = 0.0; p <= 1.0; p += 0.05) {
        expect(levelGain(p), lessThanOrEqualTo(1.0));
      }
    });
  });
}
