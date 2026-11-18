# Ambient Sound Loop

An ambient and sleep sound app that plays for **any** duration — minutes to days — with no audible loop points or repetition. The sound engine is a portable C++20 library (`libambientsynth`) behind a flat C ABI, driven by thin per-platform audio layers.

See [`docs/PLAN.md`](docs/PLAN.md) for the full design and roadmap.

## Status: Phase 1 (procedural core + desktop harness)

| Done | Not yet |
| --- | --- |
| White / pink / brown noise (xoshiro256\*\*, Kellet pink filter, leaky-integrator brown), decorrelated stereo, all colours level-matched | Harmonic drones, binaural / isochronic tones |
| Click-free colour and volume changes (one-pole smoothing) | Recorded stems (Engine B), seam matcher, granular |
| Session timer kept in rendered audio time, frame-accurate, survives sample-rate changes | Mobile platform layers, UI |
| S-curve fade-in, squared raised-cosine fade-out ending in true silence, stop-with-fade | A true look-ahead limiter (a soft clipper above −2 dBFS guards the output for now) |
| Lock-free SPSC command queue, atomics for parameters, FTZ/DAZ on the render thread, zero allocations while rendering | |
| `ambient_play` desktop player (miniaudio) | |

## Layout

```text
core-cpp/                 libambientsynth (C++20)
  include/ambient_engine.h  public C ABI — the only header UIs/platforms include
  src/dsp/                  generators and filters (header-only, allocation-free)
  src/engine/               engine, SPSC queue, denormal guard
  tests/                    unit tests (ctest)
platform-audio/desktop/   ambient_play: miniaudio harness for listening tests
docs/PLAN.md              design and roadmap
```

## Build and test

Needs CMake ≥ 3.20 and a C++20 compiler. Configuring downloads `miniaudio.h` (pinned version and SHA-256); pass `-DAMBIENT_BUILD_DESKTOP=OFF` to build only the library and tests offline.

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
| Android SDK | `~/Library/Android/sdk` | Command-line tools, no Android Studio. Emulator `ambient_phone` (Pixel 8, API 36, arm64). |
| Xcode 27.2 + iOS 27 Simulator | `/Applications/Xcode.app` | |
| CocoaPods | `/opt/homebrew/bin/pod` | From the native arm64 Homebrew. |

`~/.zshrc` sets `ANDROID_HOME` and `JAVA_HOME` and puts Flutter and the Android `platform-tools`, `emulator` and `cmdline-tools` on `PATH`. `/opt/homebrew/bin` goes **last**, because `/usr/local` holds an Intel (Rosetta) Homebrew that stays the default `brew`; install arm64 tools with `/opt/homebrew/bin/brew`.

```bash
flutter doctor
flutter emulators --launch ambient_phone          # Android emulator
xcrun simctl boot "iPhone 18 Pro" && open -a Simulator
flutter devices
flutter run -d <device-id>                        # from app-ui/
```

**Android phone:** Settings → About phone → tap *Build number* seven times, then Settings → System → Developer options → *USB debugging* on. Connect by USB, accept the "Allow USB debugging?" prompt on the phone, and check that it appears in `adb devices` and `flutter devices`.

## Listen

```bash
./build/platform-audio/desktop/ambient_play --color brown --duration 1h37m --fade-out 5m --volume 0.4
./build/platform-audio/desktop/ambient_play --color pink        # until Enter (3 s fade)
```

Durations take seconds (`90`) or units (`1h37m15s`). Defaults: pink, until stopped, 5 s fade-in, 60 s fade-out, volume 0.5.

## Engine rules

The render callback (`ambient_engine_render`) never allocates, locks, does I/O or throws; a test counts allocations while rendering. Everything the UI changes goes through atomics or the SPSC queue. See the threading contract at the top of `ambient_engine.h`.
