// Host side of the store screenshots. Taps through the real app and captures
// each state with `xcrun simctl io <device> screenshot`, so the Simulator's
// status bar (overridden to 9:41) is included.
//
//   SHOTS_DEVICE=<udid> SHOTS_DIR=<dir> SHOTS_PREFIX=iphone \
//     flutter drive -d <udid> --target=test_driver/store_screenshots.dart
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  final device = Platform.environment['SHOTS_DEVICE']!;
  final dir = Platform.environment['SHOTS_DIR']!;
  final prefix = Platform.environment['SHOTS_PREFIX'] ?? 'shot';
  late FlutterDriver driver;

  Future<void> shot(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final r = await Process.run('xcrun', ['simctl', 'io', device, 'screenshot', '$dir/$prefix-$name.png']);
    if (r.exitCode != 0) throw StateError('screenshot failed: ${r.stderr}');
  }

  setUpAll(() async => driver = await FlutterDriver.connect());
  tearDownAll(() async => driver.close());

  test('store screenshots', () async {
    await driver.waitFor(find.text('8h'));
    await shot('1-stopped');

    await driver.tap(find.bySemanticsLabel('Play'));
    await Future<void>.delayed(const Duration(seconds: 8));
    await shot('2-playing');
    await driver.tap(find.bySemanticsLabel('Stop'));
    await Future<void>.delayed(const Duration(seconds: 6));

    await driver.tap(find.bySemanticsLabel('Until I stop'));
    await shot('3-until-i-stop');

    await driver.tap(find.text('Exact'));
    await driver.waitFor(find.text('Done'));
    final picker = find.byType('LengthPicker');
    if (Platform.environment['SHOTS_WIDE'] == '1') {
      final fields = find.descendant(of: picker, matching: find.byType('TextField'), firstMatchOnly: true);
      await driver.tap(fields);
      await driver.enterText('1');
    } else {
      for (final k in ['1', '3', '7', '1', '5']) {
        await driver.tap(find.descendant(of: picker, matching: find.text(k)));
      }
    }
    await shot('4-exact');
    await driver.tap(find.text('Cancel'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
