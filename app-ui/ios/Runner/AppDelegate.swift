import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var routeObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "dev.humspan/session",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "setListening" {
        result(nil)
      } else if call.method == "outputRoute" {
        result(Self.isSpeakerRoute())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    if let routeObserver {
      NotificationCenter.default.removeObserver(routeObserver)
    }
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { note in
      // Every route change: the boom follows the speaker in and out.
      channel.invokeMethod("outputRoute", arguments: Self.isSpeakerRoute())
      guard
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
      else { return }
      channel.invokeMethod("outputLost", arguments: nil)
    }
  }

  /// True when audio plays from the device's own speaker.
  private static func isSpeakerRoute() -> Bool {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    return !outputs.isEmpty && outputs.allSatisfy { $0.portType == .builtInSpeaker }
  }
}
