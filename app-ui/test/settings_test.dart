import 'package:ambient_app/src/session/length.dart';
import 'package:ambient_app/src/session/settings.dart';
import 'package:ambient_native/ambient_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('first launch: Pink, 30% volume, 8 h, binaural off at 4 Hz', () async {
    final settings = await SettingsStore(SharedPreferencesAsync()).load();
    expect(settings.color, NoiseColor.pink);
    expect(settings.volumePercent, 30);
    expect(settings.length, SessionLength.timed(const Duration(hours: 8)));
    expect(settings.binauralOn, isFalse);
    expect(settings.beatHz, 4);
  });

  test('every setting round-trips through a new store', () async {
    const saved = SessionSettings(
      color: NoiseColor.brown,
      volumePercent: 72,
      length: TimedLength(Duration(hours: 1, minutes: 37, seconds: 15)),
      binauralOn: true,
      beatHz: 10,
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
    await prefs.setInt('volume', 400);
    await prefs.setInt('lengthSeconds', -5);
    await prefs.setInt('beatHz', 7);
    final loaded = await SettingsStore(prefs).load();
    expect(loaded, SessionSettings.firstLaunch);
  });
}
