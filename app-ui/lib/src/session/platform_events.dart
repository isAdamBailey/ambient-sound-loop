/// Android audio focus and headphones-out, and the iOS route report.
/// Desktop runners have no channel; a missing plugin is ignored.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'session_controller.dart';

const sessionChannelName = 'dev.ambientsoundloop/session';

/// Applies one call from the platform channel to the session.
void applySessionEvent(SessionController controller, String method) {
  switch (method) {
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
      applySessionEvent(controller, call.method);
    });
    controller.addListener(_syncListening);
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

  void dispose() {
    controller.removeListener(_syncListening);
    _channel.setMethodCallHandler(null);
    if (_listening) {
      _listening = false;
      _tail = _tail.then((_) => _send(false));
    }
  }
}
