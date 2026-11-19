import 'package:humspan_native/humspan_native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_name.dart';
import 'src/session/audio_port.dart';
import 'src/session/now_playing.dart';
import 'src/session/platform_events.dart';
import 'src/session/session_controller.dart';
import 'src/session/settings.dart';
import 'src/ui/session_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore(SharedPreferencesAsync());
  final settings = await store.load();

  final NativePlayer player;
  try {
    player = NativePlayer.create(seed: DateTime.now().microsecondsSinceEpoch);
  } on StateError {
    runApp(const _AudioFailedApp());
    return;
  } on ArgumentError {
    runApp(const _AudioFailedApp());
    return;
  }

  final controller = SessionController(
    audio: FfiAudioPort(player),
    settings: settings,
    reroute: _reroute(),
    onSettingsChanged: store.save,
  );
  final nowPlaying = NowPlaying(controller, FlutterNowPlaying());
  final platform = PlatformEvents(controller);

  runApp(SessionApp(
    controller: controller,
    onDispose: () {
      nowPlaying.dispose();
      platform.dispose();
      controller.dispose();
      player.dispose();
    },
  ));
}

RerouteBehavior _reroute() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return RerouteBehavior.restartStream;
    case TargetPlatform.iOS:
      return RerouteBehavior.ignore;
    default:
      return RerouteBehavior.pauseSession;
  }
}

class SessionApp extends StatefulWidget {
  const SessionApp({super.key, required this.controller, required this.onDispose});

  final SessionController controller;
  final VoidCallback onDispose;

  @override
  State<SessionApp> createState() => _SessionAppState();
}

class _SessionAppState extends State<SessionApp> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: sessionTheme(),
      home: SessionScreen(controller: widget.controller),
    );
  }
}

class _AudioFailedApp extends StatelessWidget {
  const _AudioFailedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: sessionTheme(),
      home: Scaffold(
        backgroundColor: SessionColors.ground,
        body: Center(child: Text('Audio is unavailable on this device.', style: SessionText.body)),
      ),
    );
  }
}
