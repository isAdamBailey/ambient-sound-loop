# Which UI toolkits can share one session screen

Researched 16 November 2026, from each project's own docs, source, or API reference. This note does not choose a toolkit.

The question is which maintained toolkit can ship one codebase that draws a real window or screen on macOS, Windows, Linux, iOS, and Android, and can call the flat C functions in `core-cpp/include/humspan_engine.h` from the UI control thread. A separate native audio layer calls `humspan_engine_render`. The UI also has to be able to put play/stop and a time readout on the iOS now-playing surface and the Android media session.

A target counts as shipped when that project's maintained release documents it as supported. A community port, a beta, or a backend the project says it does not support is recorded, and does not by itself satisfy the five platforms. "Qualifies" below means the maintained release covers all five and UI code can make the C call off the audio thread. Where the docs show no now-playing API, that gap is stated even if the verdict is still qualifies, because the call path is ordinary platform interop rather than a media widget.

JetBrains' own survey of cross-platform frameworks also names Uno Platform, Ionic, and NativeScript beside Flutter, React Native, and .NET MAUI, so those three are judged from their own docs as well. <https://kotlinlang.org/docs/multiplatform/cross-platform-frameworks.html>

## Flutter

**Platforms.** Flutter's docs say one codebase deploys to mobile, web, and desktop. Desktop support is a native Windows, macOS, or Linux app, and `flutter create` adds iOS, Android, web, and desktop targets to the same project. <https://docs.flutter.dev/platform-integration/desktop> <https://flutter.dev/development>

As of Flutter 3.50, the supported deployment platforms include Android, iOS, Windows 10 and 11, macOS, Debian, and Ubuntu. The Flutter team marks those as supported, not community or beta. macOS Intel is being phased out: macOS Tahoe (26) is the last Intel release, and macOS Golden Gate (27) requires Apple Silicon. Linux support is stated for Debian 10–13 and Ubuntu 20.04–24.04 LTS, not for every distribution. <https://docs.flutter.dev/reference/supported-platforms>

**Calling C.** `dart:ffi` is the core library for calling C ABI functions. Bindings can be generated with `package:ffigen`. FFI calls are synchronous and run on the thread that calls them. A call from UI code runs on the app's main UI thread. That is the control thread, and it is not an audio callback. A heavy call can be moved to another isolate, but nothing in the docs requires that for a short call. <https://docs.flutter.dev/interop/dart-ffi> <https://dart.dev/interop/c-interop> <https://docs.flutter.dev/interop/ffigen>

**Now playing.** The Flutter 3.50 docs do not name `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, Android `MediaSession`, or an official plugin that publishes play/stop and a time readout. The same release's docs do tell you how to call platform APIs yourself: `package:ffigen` for C and for Apple Objective-C frameworks, and `package:jnigen` for Java and Kotlin. <https://docs.flutter.dev/release/whats-new> <https://docs.flutter.dev/interop/ffigen>

A proposal to add media notifications to the first-party `video_player` plugin, using `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` on iOS and Media3 `MediaSession` on Android, was still a draft in March 2026 because the Flutter packages reviewer asked for a design review before it could land. It is not a shipped API. <https://github.com/flutter/packages/issues/10915>

**Maintenance.** Flutter 3.50.0 is the top entry on the stable-channel release list. The docs date that release to 11 November 2026. <https://docs.flutter.dev/release/release-notes> <https://docs.flutter.dev/release/whats-new>

**Qualifies.** Flutter 3.50 supports all five platforms from one project, and `dart:ffi` runs the C call on the UI thread that invokes it. The docs do not ship a now-playing widget; the documented route is FFI or a platform binding.

## React Native

**Platforms.** React Native's own out-of-tree page says the framework is not only Android and iOS, and then splits other targets into partner and community projects. Partners: React Native macOS ("macOS and Cocoa"), React Native Windows ("Microsoft's Universal Windows Platform"), plus visionOS and OpenHarmony. Community: tvOS, React Native Web, and "React Native Skia", which "currently supports Linux and macOS." Linux appears only on that community line. <https://reactnative.dev/docs/out-of-tree-platforms>

React Native 0.88, released 19 October 2026, is the latest stable line announced on the React Native blog. Its support table, on the 0.85 docs, lists 0.88 as the active stable release and 0.89 as a future release dated 7 December 2026. <https://reactnative.dev/blog/2026/10/19/react-native-0.88> <https://reactnative.dev/docs/0.85/releases>

React Native Windows 0.85.0 was published on 20 October 2026 against React Native 0.85.3. That release requires the New Architecture, builds with the Windows App SDK, and exposes `ReactNativeWin32App`, so the desktop target is a native Win32/WinUI window rather than a page in a desktop browser. It is a partner project and it lags the core 0.88 line. <https://github.com/microsoft/react-native-windows/releases/tag/react-native-windows_v0.85.0>

React Native macOS 0.83.0 was published on 30 September 2026, synced to React Native 0.83.10. The out-of-tree page describes it as Cocoa, which is a native macOS window. It is a partner project and several minors behind 0.88. <https://github.com/microsoft/react-native-macos/releases/tag/react-native-macos%400.83.0> <https://reactnative.dev/docs/out-of-tree-platforms>

**Calling C.** The current docs' path for native code is a Turbo Native Module. A pure C++ module is written once, registered on each platform, and called from JavaScript. The guide shows the call coming from a JS press handler. The archived native-module guide says a module must not assume which thread it is called on, because that assignment can change. Nothing in those docs places the call on an audio callback, so it can stay off the audio thread. They also do not promise that the native method runs on the UI thread. <https://reactnative.dev/docs/the-new-architecture/pure-cxx-modules> <https://reactnative.dev/docs/turbo-native-modules-introduction> <https://archive.reactnative.dev/docs/native-modules-android>

**Now playing.** The React Native docs fetched here do not name `MPNowPlayingInfoCenter` or Android `MediaSession`.

Expo's audio library, in the SDK 58 reference, does. `setActiveForLockScreen` puts Expo's own player on the lock screen, and the written behaviour is a media notification and lock-screen controls on Android and iOS. `AudioMetadata` fields are title, artist, album title, and artwork. There is no elapsed-time field. `AudioLockScreenOptions.isLiveStream` hides "the duration and scrub bar" for a live stream, so a duration readout exists only as a property of that player. The docs do not show publishing play/stop and a clock for an engine Expo Audio is not playing. <https://docs.expo.dev/versions/latest/sdk/audio>

**Maintenance.** React Native 0.88 is the current stable core release (19 October 2026). React Native Windows 0.85.0 (20 October 2026) and React Native macOS 0.83.0 (30 September 2026) are still publishing. Neither the core nor those partner releases documents a maintained Linux desktop.

**Does not qualify.** There is no maintained Linux desktop target. The only Linux mention on the official platform page is the community Skia renderer.

## Compose Multiplatform

**Platforms.** Compose Multiplatform's stability table marks Android, iOS, and desktop (JVM) Stable, and web (Kotlin/Wasm) Beta. Compose Multiplatform 1.12.2's minimums are Android 5.0, iOS 14, macOS 13 arm64, Windows 10 (x86-64 and arm64), and Ubuntu 20.04 (x86-64 and arm64). Desktop is a JVM target, separate from the browser target. The macOS row in that table is arm64 only. <https://kotlinlang.org/docs/multiplatform/supported-platforms.html> <https://kotlinlang.org/docs/multiplatform/compose-compatibility-and-versioning.html> <https://kotlinlang.org/compose-multiplatform/>

JetBrains states that iOS reached Stable in Compose Multiplatform 1.8.0 (May 2025) and that Android, iOS, and desktop are production-ready. On Android, Compose Multiplatform runs on Jetpack Compose. <https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/> <https://kotlinlang.org/compose-multiplatform/>

**Calling C.** The mechanism is different on each target.

On iOS, and on any Kotlin/Native target, `cinterop` reads C headers and generates Kotlin bindings. JetBrains marks that C-library import Beta: generated declarations need `@ExperimentalForeignApi`. Platform libraries that ship with Kotlin/Native, such as Foundation and UIKit, are not under that same blanket opt-in. <https://kotlinlang.org/docs/native-c-interop.html>

On Android, the Android NDK documents the call as `System.loadLibrary` plus a Kotlin `external` function, implemented in C through JNI. The call is an ordinary method call on the thread that invokes it. <https://github.com/android/ndk/wiki/JNI>

Desktop Compose is the JVM target, not Kotlin/Native, so `cinterop` is not the desktop path. A JVM native method is JNI. <https://kotlinlang.org/docs/multiplatform/supported-platforms.html> <https://docs.oracle.com/en/java/javase/21/docs/specs/jni/intro.html>

Android's Compose docs say composable functions themselves may be reordered, and that side effects belong in callbacks such as `onClick`, which always run on the UI thread. JetBrains does not, on the pages read here, restate that thread rule for a desktop or iOS click. A `cinterop` or JNI call does not move itself onto an audio thread. <https://developer.android.com/develop/ui/compose/mental-model>

**Now playing.** The Compose and Kotlin Multiplatform docs read here do not name `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, or Android `MediaSession`. They do say Apple SDK dependencies are available to iOS source sets as prebuilt libraries, with Foundation and Core Bluetooth as the examples, and that another Objective-C framework can be imported with `cinterop`. They do not name MediaPlayer. On Android, the app is a Jetpack Compose Android app, so the Android media APIs are platform code rather than a Compose API. <https://kotlinlang.org/docs/multiplatform/multiplatform-ios-dependencies.html> <https://kotlinlang.org/compose-multiplatform/>

**Maintenance.** Compose Multiplatform 1.12.2 is the version the compatibility page documents as the current release, with Android, iOS, and desktop Stable. The C-library importer remains Beta. <https://kotlinlang.org/docs/multiplatform/compose-compatibility-and-versioning.html> <https://kotlinlang.org/docs/native-c-interop.html>

**Qualifies.** The shared UI is stable on all five, and each target has a documented C call that UI code can make off the audio thread. The sharp caveat is that the iOS call into a C library is still a Beta API.

## .NET MAUI

**Platforms.** Microsoft's supported-platform page for .NET MAUI lists Android, iOS, macOS through Mac Catalyst, and Windows through WinUI 3. Linux is not on that list. The same docs say MAUI uses one multi-targeted project for those platforms. Mac Catalyst is a real macOS window: the `Window` type can open and activate windows on Mac Catalyst and Windows, and window position and size can be set there. <https://learn.microsoft.com/en-us/dotnet/maui/supported-platforms?view=net-maui-10.0> <https://learn.microsoft.com/en-us/dotnet/maui/platform-integration/invoke-platform-code?view=net-maui-10.0> <https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/window?view=net-maui-10.0>

A Linux GTK4 backend exists under experimental platform backends. Microsoft's page says it is experimental, will change between releases, and is not officially supported. The MAUI team's note on the same work says there is no roadmap to make Linux an officially supported target. <https://learn.microsoft.com/en-us/dotnet/maui/developer-tools/platform-backends/linux-gtk4?view=net-maui-10.0> <https://github.com/dotnet/maui/discussions/31649>

**Calling C.** .NET's source-generated P/Invoke (`LibraryImport` on a partial method) is the current interop for a C ABI, available since .NET 7. `DllImport` remains the older runtime stub. A MAUI button handler runs on the main UI thread; `MainThread` is how other threads get back there. A P/Invoke made from that handler stays on the calling thread, which is not an audio callback. <https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation> <https://learn.microsoft.com/en-us/dotnet/maui/platform-integration/appmodel/main-thread?view=net-maui-10.0>

**Now playing.** The MAUI docs do not have a now-playing control. They do say that when MAUI has no API, app code calls the platform APIs, from the platform folders of the same project. The .NET iOS and Mac Catalyst bindings expose `MPNowPlayingInfoCenter` and `MPNowPlayingInfo`, including `ElapsedPlaybackTime`, and `MPRemoteCommandCenter` for remote player events. The .NET Android binding exposes `Android.Media.Session.MediaSession` and `MediaSession.Callback`, including `OnPlay` and `OnPause`, and describes the session as the way an app publishes playback to other controllers. <https://learn.microsoft.com/en-us/dotnet/maui/platform-integration/invoke-platform-code?view=net-maui-10.0> <https://learn.microsoft.com/en-us/dotnet/api/mediaplayer.mpnowplayinginfocenter?view=net-ios-26.4-10.0> <https://learn.microsoft.com/en-us/dotnet/api/mediaplayer.mpnowplayinginfo?view=net-ios-26.2-10.0> <https://learn.microsoft.com/en-us/dotnet/api/mediaplayer.mpremotecommandcenter?view=net-ios-26.5-10.0> <https://learn.microsoft.com/en-us/dotnet/api/android.media.session.mediasession?view=net-android-37.0> <https://learn.microsoft.com/en-us/dotnet/api/android.media.session.mediasession.callback?view=net-android-37.0>

**Maintenance.** .NET 11 shipped on 10 November 2026 and is the current Standard Term Support release, supported until November 2028. .NET 10 remains the Long Term Support release, also until November 2028. The MAUI docs include a .NET 11 what's-new page. <https://learn.microsoft.com/en-us/dotnet/core/releases-and-support> <https://learn.microsoft.com/en-us/lifecycle/products/microsoft-net-and-net-core> <https://learn.microsoft.com/en-us/dotnet/maui/whats-new/dotnet-11?view=net-maui-10.0>

**Does not qualify.** Linux is not a supported MAUI platform. The GTK4 backend is explicitly unsupported and has no roadmap into support.

## Qt

**Platforms.** The Qt 6.12 supported-platforms page lists desktop Linux (specified distributions, including Ubuntu 22.04 and 24.04 and Debian 11 and 12), macOS 14.4 and later, Windows 10 and 11, Android 9 through 16, and iOS 18 and later. Those are the tested, maintained configurations. HarmonyOS is called out separately as a technology preview. Qt for WebAssembly is a browser target, separate from the desktop and mobile rows. The deployment index lists Android, iOS, Linux, macOS, and Windows as the places a Qt application is deployed. <https://doc.qt.io/qt-6/supported-platforms.html>

**Calling C.** Qt UI code is C++. Widgets may be used only on the main thread, which Qt calls the GUI thread. A slot handling a widget event on that thread calls the C functions directly; there is no FFI layer. Qt also has an audio callback if the app uses Qt Multimedia's device APIs. That callback is not the GUI thread, and the control calls do not have to go through it. <https://doc.qt.io/qt-6/threads-qobject.html> <https://doc.qt.io/qt-6/multimediaoverview.html>

**Now playing.** Qt Multimedia's overview lists playback, devices, and capture. It does not list the system now-playing surface or a media-session publisher. `QMediaPlayer` plays a URL. <https://doc.qt.io/qt-6/multimediaoverview.html> <https://doc.qt.io/qt-6/qmediaplayer.html>

`QMediaSessionController` is a different product. It lives in Qt for Android Automotive, and it controls media sessions already on the device. It is not an API for publishing this app's play/stop and clock, and it is not the phone MediaSession. <https://doc.qt.io/QtAndroidAutomotive/qmediasessioncontroller.html>

The documented way to reach platform APIs is `QJniObject` for Java and Android types, and an Objective-C++ `.mm` file for Apple frameworks. Those calls can be made from the GUI thread. The Qt docs do not show the now-playing classes themselves. <https://doc.qt.io/qt-6/qjniobject.html> <https://doc.qt.io/qt-6/ios.html>

**Maintenance.** The current Qt 6 documentation set read here is Qt 6.12, and that page says supported platforms are actively maintained. Qt 6.12 is also noted as the last version that will support Windows 10. <https://doc.qt.io/qt-6/supported-platforms.html>

**Qualifies.** Qt 6.12 officially supports all five, and GUI-thread C++ calls the C ABI directly. Now playing is platform code through JNI or Objective-C++, not a Qt media API.

## JUCE

**Platforms.** The JUCE readme describes one C++ framework for desktop and mobile applications, with project export for Xcode (macOS and iOS), Visual Studio, Android Studio, and Linux makefiles. Its deployment targets are macOS 10.11, Windows 10 version 1607, mainstream Linux distributions, iOS 12, and Android 7 (API 24). Linux 32-bit ARM "should work but [is] not regularly tested." These are JUCE's own targets, not a community port. <https://github.com/juce-framework/JUCE/blob/master/README.md>

**Calling C.** Application UI runs on the message thread. `MessageManager` is the event-dispatch loop, and `callFunctionOnMessageThread` runs a function there. `AudioProcessor::processBlock` is explicitly the audio thread, and JUCE says any interaction with the UI from that callback is out of the question. `getActiveEditor` may be called only from the message thread. The session screen does not have to install an audio callback: the control calls are C++ calls from message-thread UI code, straight into the C ABI. <https://docs.juce.com/master/classjuce_1_1MessageManager.html> <https://docs.juce.com/master/classjuce_1_1AudioProcessor.html>

**Now playing.** The JUCE module docs and the readme do not document `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, or a public API that publishes an Android media session for an engine JUCE is not playing. `juce_video` contains an internal Android `MediaSessionCallback` used by the video module. That is not a documented session-screen API. <https://github.com/juce-framework/JUCE/blob/master/README.md> <https://github.com/juce-framework/JUCE/blob/master/modules/juce_video/native/juce_Video_android.h>

A JUCE iOS or Android app is a native Xcode or Android Studio project, so the same C++ can call the OS media frameworks. JUCE does not document that step.

**Maintenance.** `master` defines `JUCE_MAJOR_VERSION` 9, `JUCE_MINOR_VERSION` 0, `JUCE_BUILDNUMBER` 5. The GitHub releases page shows 9.0.5 published on 2 November 2026. <https://github.com/juce-framework/JUCE/blob/master/modules/juce_core/system/juce_StandardHeader.h> <https://github.com/juce-framework/JUCE/releases>

**Qualifies.** JUCE 9.0.5 ships all five from one C++ codebase, and the message thread can call the C ABI without taking the audio callback. The docs do not show now playing.

## Uno Platform

JetBrains lists Uno beside MAUI as a single-codebase .NET UI for Android, iOS, macOS, Linux, and Windows. <https://kotlinlang.org/docs/multiplatform/cross-platform-frameworks.html>

**Platforms.** Uno's requirements page says applications run on Android, iOS, Web, macOS desktop, Linux, and Windows. Desktop targets use `net10.0-desktop`: Skia on Windows, macOS 10.15 and later, and Linux. Linux environments named there are X11 and the framebuffer, which is a window on X11 rather than a desktop browser. WebAssembly is a separate `net10.0-browserwasm` target. Android uses `net10.0-android` (Android 7.0 and later). iOS uses `net10.0-ios` (iOS 15 and later). <https://platform.uno/docs/articles/getting-started/requirements.html>

Uno Platform 7.0 makes Skia the only UI renderer on every target, including Android and iOS, and removes the Mac Catalyst head. macOS stays on `net10.0-desktop`. The docs say this does not drop Android, iOS, macOS, Windows, Linux, or WebAssembly. <https://platform.uno/docs/articles/migrating-to-uno-7.html>

**Calling C.** Uno is a .NET projection of WinUI and "provides access to the existing .NET libraries." The C call is the same `LibraryImport` / `DllImport` P/Invoke .NET documents for MAUI. UI events are on the UI thread of that .NET app. Uno's WebAssembly notes treat `DllImport` as the loader for a native library, which is the same mechanism. <https://platform.uno/docs/articles/uno-development/uno-internals-overview.html> <https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation> <https://platform.uno/docs/articles/common-issues-wasm.html>

**Now playing.** Uno's `MediaPlayerElement` feature table lists "Player controls on locked screen support" as not implemented on iOS and Android, on WebAssembly, and on Skia. That control plays through `AVPlayer` on iOS and `AndroidMediaPlayer` on Android, so it is also a player, not a session for an external engine. <https://platform.uno/docs/articles/controls/MediaPlayerElement.html>

The docs do not name `MPNowPlayingInfoCenter` or `MediaSession`. They do say a Uno app can use the rest of .NET, and the .NET bindings cited under MAUI are those APIs. Native views can be hosted on Android, iOS, and macOS. <https://platform.uno/docs/articles/uno-development/uno-internals-overview.html> <https://platform.uno/docs/articles/native-views.html>

**Maintenance.** The requirements page is written against the `net10.0` target frameworks and against the .NET 11 Android floor (API 24). The 7.0 migration guide is the current rendering model. <https://platform.uno/docs/articles/getting-started/requirements.html> <https://platform.uno/docs/articles/migrating-to-uno-7.html>

**Qualifies.** Uno's own platform list includes all five, desktop is an X11 or AppKit window rather than a browser, and .NET P/Invoke can run on the UI thread. The toolkit's media player explicitly does not implement lock-screen controls.

## Ionic

JetBrains lists Ionic as a single-codebase mobile UI built with HTML, CSS, and JavaScript, using Cordova and Capacitor for device APIs. <https://kotlinlang.org/docs/multiplatform/cross-platform-frameworks.html>

Ionic's own cross-platform page says an app can run as Android, iOS, Electron, and a progressive web app from one codebase, and then says Electron and desktop browsers can run Ionic apps but desktop usage is not officially supported. The browser-support page repeats that: desktop browsers are possible, and desktop usage is not officially supported. The supported rows are Android and iOS. Capacitor is described as a runtime for web apps on iOS, Android, Electron, and the web. <https://ionicframework.com/docs/core-concepts/cross-platform> <https://ionicframework.com/docs/reference/browser-support> <https://ionicframework.com/docs/reference/glossary>

The docs still publish an Ionic v9 row in the browser-support table, so the project is maintaining current docs. Those docs do not show a native C ABI binding; device access is Capacitor or Cordova plugins. They also do not show `MPNowPlayingInfoCenter` or Android `MediaSession`.

**Does not qualify.** Ionic says desktop use is not officially supported, and the desktop path it does name is Electron, a desktop browser shell.

## NativeScript

JetBrains lists NativeScript as a JavaScript framework for Android and iOS native UI. <https://kotlinlang.org/docs/multiplatform/cross-platform-frameworks.html>

NativeScript's own introduction says the supported platform runtimes are `@nativescript/android`, `@nativescript/ios`, and `@nativescript/visionos`, and describes the cross-platform case as Web, iOS, Android, and Vision Pro. The environment setup table is Android and iOS only. There is no Windows, Linux, or macOS desktop runtime in that list. <https://docs.nativescript.org/> <https://docs.nativescript.org/setup/>

The docs are current enough to document visionOS. They do show direct access to native platform APIs from JavaScript, which is how an Android or iOS app would reach media session and now playing. They do not name those classes in the pages read here. That does not add the missing desktops.

**Does not qualify.** NativeScript does not ship a desktop window on macOS, Windows, and Linux.

## What this does not decide

Flutter, Compose Multiplatform, Qt, JUCE, and Uno Platform meet the five-platform bar, with the caveats above: Compose's iOS C import is Beta, and none of the five documents a ready-made now-playing control for an engine the toolkit does not own. React Native, .NET MAUI, Ionic, and NativeScript do not meet it. The missing piece for React Native and MAUI is a maintained Linux desktop; for Ionic and NativeScript it is a supported desktop window at all.

No toolkit is selected.
