# CLAUDE.md

Guidance for Claude Code in this repository. Design and roadmap: `docs/PLAN.md`.

## Commands

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # add -DAMBIENT_BUILD_DESKTOP=OFF offline
cmake --build build
ctest --test-dir build --output-on-failure
./build/platform-audio/desktop/ambient_play --help
```

## Rules

- **Real-time safety.** Nothing reachable from `ambient_engine_render` may allocate, lock, do I/O, throw or log. `testRenderDoesNotAllocate` counts global `operator new` calls while rendering; exercise any new render-path feature inside it.
- **Control → audio** goes only through `std::atomic` parameters (smoothed on the audio thread) or the `SpscQueue` of `Command`s. Never share other mutable state between threads.
- **The C ABI is the boundary.** UIs and platform layers include only `core-cpp/include/ambient_engine.h`. Keep it C (no C++ types), and document the threading of each new function there.
- **Time, not samples.** The session timer is seconds of rendered audio, folded on `ambient_engine_set_sample_rate`. Do not store durations as sample counts.
- **Levels.** Every generator is normalised to `dsp::kNoiseRms` so switching keeps loudness; a new generator gets a level test like `testSpectralSlopeAndLevel`.
- Tests are a plain executable (`core-cpp/tests/engine_tests.cpp`, `CHECK` macro): add a `test…()` function and call it from `main()`.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues. See `docs/agents/issue-tracker.md`.
