# Humspan

An ambient and sleep sound app that plays for **any** duration — minutes to days — with no audible loop points or repetition. The sound engine is a portable C++20 library (`libhumspansynth`) behind a flat C ABI, driven by thin per-platform audio layers.

See [`docs/PLAN.md`](docs/PLAN.md) for the full design and roadmap.

## Status

The procedural engine and `humspan_play` listening harness are in place, including pause/resume, interruption ducking and a normalised binaural layer. The session screen (`app-ui/`, issue #10) is the app: one Flutter screen on desktop, iOS and Android, with restore and system now-playing. On an Android phone it has been checked for lock-screen controls, headphone unplug, a call duck, and a full `1h 37m` session.

| Done | Not yet |
| --- | --- |
| White / pink / brown noise (xoshiro256\*\*, Kellet pink filter, leaky-integrator brown), decorrelated stereo. White and pink share a level; brown is 9 dB above that so it matches by ear and stays clean on a phone speaker | Harmonic drones, isochronic tones |
| Click-free colour changes (one-pole smoothing); binaural beat, on/off and 2–10 Hz; optional boom, alternating ears at 8 / 4 / 2 s | Recorded stems (Engine B), seam matcher, granular |
| Session timer kept in rendered audio time, frame-accurate, survives sample-rate changes; pause/resume keeps it | A true look-ahead limiter (a soft clipper above −2 dBFS guards the output for now) |
| S-curve fade-in, squared raised-cosine fade-out ending in true silence, stop-with-fade, fades that shrink to fit | |
| Lock-free SPSC command queue, atomics for parameters, FTZ/DAZ on the render thread, zero allocations while rendering | |
| `humspan_play` desktop player (miniaudio) | |
| Session screen app: screen, session logic, native output stream, now-playing, and the Android phone pass (lock screen, headphone unplug, call duck, `1h 37m`) | |

## Layout

```text
core-cpp/                 libhumspansynth (C++20)
  include/humspan_engine.h  public C ABI — the only header UIs/platforms include
  src/dsp/                  generators and filters (header-only, allocation-free)
  src/engine/               engine, SPSC queue, denormal guard
  tests/                    unit tests (ctest)
platform-audio/desktop/   humspan_play: miniaudio harness for listening tests
platform-audio/player/    the app's output stream (engine + miniaudio)
app-ui/                   the session screen (Flutter)
docs/PLAN.md              design and roadmap
```

## Build and test

Needs CMake ≥ 3.20 and a C++20 compiler. Configuring downloads `miniaudio.h` (pinned version and SHA-256); pass `-DHUMSPAN_BUILD_DESKTOP=OFF` to build only the library and tests offline.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

## App dev environment (macOS)

The session screen app (Flutter, `app-ui/`, issue #10) needs this toolchain. Set up on 2026-11-17; `flutter doctor` is clean apart from the Android SDK licenses, which the owner accepts with `flutter doctor --android-licenses`.

| Tool | Where | Notes |
| --- | --- | --- |
| Flutter stable (3.50) | `~/development/flutter` | Git clone of the `stable` branch, native arm64. Update with `flutter upgrade`. |
| JDK 21 (Temurin, arm64) | `~/Library/Java/JavaVirtualMachines` | Set for Flutter with `flutter config --jdk-dir "$(/usr/libexec/java_home -v 21)"`. |
| Android SDK | `~/Library/Android/sdk` | Command-line tools, no Android Studio. Emulator `humspan_phone` (Pixel 8, API 36, arm64). |
| Xcode 27.2 + iOS 27 Simulator | `/Applications/Xcode.app` | |
| CocoaPods | `/opt/homebrew/bin/pod` | From the native arm64 Homebrew. |

`~/.zshrc` sets `ANDROID_HOME` and `JAVA_HOME` and puts Flutter and the Android `platform-tools`, `emulator` and `cmdline-tools` on `PATH`. `/opt/homebrew/bin` goes **last**, because `/usr/local` holds an Intel (Rosetta) Homebrew that stays the default `brew`; install arm64 tools with `/opt/homebrew/bin/brew`.

```bash
flutter doctor
flutter emulators --launch humspan_phone          # Android emulator
xcrun simctl boot "iPhone 18 Pro" && open -a Simulator
flutter devices
cd app-ui && flutter test
cd app-ui && flutter run -d <device-id>
```

The desktop window is titled Humspan and will not shrink below 360×640. Loudness is the device volume; the screen has no volume control. On a phone, playback shows a media notification titled Humspan; unplugging headphones should pause with no sound from the speaker.

**Android phone:** Settings → About phone → tap *Build number* seven times, then Settings → System → Developer options → *USB debugging* on. Connect by USB, accept the "Allow USB debugging?" prompt on the phone, and check that it appears in `adb devices` and `flutter devices`.

## Listen

```bash
./build/platform-audio/desktop/humspan_play --color brown --duration 1h37m --fade-out 5m --volume 0.4
./build/platform-audio/desktop/humspan_play --color pink        # until Enter (3 s fade)
```

Durations take seconds (`90`) or units (`1h37m15s`). Defaults: pink, until stopped, 5 s fade-in, 60 s fade-out, volume 0.5.

## Engine rules

The render callback (`humspan_engine_render`) never allocates, locks, does I/O or throws; a test counts allocations while rendering. Everything the UI changes goes through atomics or the SPSC queue. See the threading contract at the top of `humspan_engine.h`.
