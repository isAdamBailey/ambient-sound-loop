# CLAUDE.md

Guidance for Claude Code in this repository. Design and roadmap: `docs/PLAN.md`.

## Commands

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # add -DHUMSPAN_BUILD_DESKTOP=OFF offline
cmake --build build
ctest --test-dir build --output-on-failure
./build/platform-audio/desktop/humspan_play --help
flutter doctor                              # app toolchain: README "App dev environment"
flutter emulators --launch humspan_phone    # Android emulator for this project
```

Tool shells skip `~/.zshrc`, so run `flutter`, `adb`, `pod` and `emulator` through `zsh -i -c '…'`. `/usr/local/bin/brew` is an Intel build under Rosetta; install arm64 tools with `/opt/homebrew/bin/brew`.

## Rules

- **Real-time safety.** Nothing reachable from `humspan_engine_render` may allocate, lock, do I/O, throw or log. `testRenderDoesNotAllocate` counts global `operator new` calls while rendering; exercise any new render-path feature inside it.
- **Control → audio** goes only through `std::atomic` parameters (smoothed on the audio thread) or the `SpscQueue` of `Command`s. Never share other mutable state between threads.
- **The C ABI is the boundary.** UIs and platform layers include only `core-cpp/include/humspan_engine.h`. Keep it C (no C++ types), and document the threading of each new function there.
- **Time, not samples.** The session timer is seconds of rendered audio, folded on `humspan_engine_set_sample_rate`. Do not store durations as sample counts.
- **Levels.** White and pink are normalised to `dsp::kNoiseRms`. Brown is about 9 dB above that (`BrownFilter::kOpenRms`) so it matches them by ear and stays clean on a phone speaker. A new generator gets a level test like `testSpectralSlopeAndLevel`. The session screen sets the engine gain to full scale; the device volume is the loudness control.
- Tests are a plain executable (`core-cpp/tests/engine_tests.cpp`, `CHECK` macro): add a `test…()` function and call it from `main()`.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues. See `docs/agents/issue-tracker.md`.
