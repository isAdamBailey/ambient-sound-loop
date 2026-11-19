/// Android audio focus and headphones-out, the iOS route report, and on both
/// whether the output is the device's own speaker.
/// Desktop runners have no channel; a missing plugin is ignored.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'session_controller.dart';

const sessionChannelName = 'dev.humspan/session';

/// Applies one call from the platform channel to the session.
void applySessionEvent(SessionController controller, String method, [Object? arguments]) {
  switch (method) {
    case 'outputRoute':
      if (arguments is bool) controller.outputRouteChanged(speaker: arguments);
    case 'outputLost':
      controller.routeLost();
    case 'focusLoss':
      controller.focusLost(FocusLoss.permanent);
    case 'focusTransient':
      controller.focusLost(FocusLoss.transient);
    case 'focusDuck':
      controller.focusLost(FocusLoss.canDuck);
    case 'focusGain':
      controller.focusGained();
  }
}

/// Listens for platform session events and asks Android to hold audio focus
/// and the headphones-out receiver while a session is playing.
class PlatformEvents {
  PlatformEvents(this.controller, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(sessionChannelName) {
    _channel.setMethodCallHandler((call) async {
      applySessionEvent(controller, call.method, call.arguments);
    });
    controller.addListener(_syncListening);
    _tail = _tail.then((_) => _queryRoute());
  }

  final SessionController controller;
  final MethodChannel _channel;
  bool _listening = false;
  Future<void> _tail = Future<void>.value();

  void _syncListening() {
    final listen = controller.phase == SessionPhase.playing;
    if (listen == _listening) return;
    _listening = listen;
    _tail = _tail.then((_) => _send(listen));
  }

  Future<void> _send(bool listen) async {
    try {
      await _channel.invokeMethod<void>('setListening', listen);
    } on MissingPluginException {
      // Desktop runners have no route or focus glue.
    } on PlatformException {
      // The activity was not ready; the next session edge tries again.
      _listening = !listen;
    }
  }

  /// The route at launch; later changes arrive as 'outputRoute' calls.
  Future<void> _queryRoute() async {
    try {
      final speaker = await _channel.invokeMethod<bool>('outputRoute');
      if (speaker != null) controller.outputRouteChanged(speaker: speaker);
    } on MissingPluginException {
      // Desktop runners have no route glue: keep the deep boom.
    } on PlatformException {
      // No answer: keep the deep boom until a route change reports.
    }
  }

  void dispose() {
    controller.removeListener(_syncListening);
    _channel.setMethodCallHandler(null);
    if (_listening) {
      _listening = false;
      _tail = _tail.then((_) => _send(false));
    }
  }
}
