// App entry for store screenshots: the real app with the Flutter Driver
// extension, starting from a fixed mix. Driven by
// store_screenshots_test.dart; see docs/store/app-store/README.md.
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:humspan/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = SharedPreferencesAsync();
  await prefs.setBool('noiseOn', true);
  await prefs.setString('color', 'brown');
  await prefs.setInt('lengthSeconds', 8 * 3600);
  await prefs.setBool('binauralOn', true);
  await prefs.setInt('beatHz', 4);
  await prefs.setBool('boomOn', true);
  await prefs.setInt('boomSeconds', 8);
  await prefs.setDouble('noiseLevel', 0.8);
  await prefs.setDouble('binauralLevel', 0.55);
  await prefs.setDouble('boomLevel', 0.65);
  await prefs.setBool('mono', false);
  await app.main();
}
