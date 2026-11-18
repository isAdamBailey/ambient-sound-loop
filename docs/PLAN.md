# Project Plan: Infinite Non-Repeating Ambient & Sleep Sound Application

> **Revision 2 (2026-11-16).** Changes from the first draft, after review:
> per-pass randomisation for recorded stems (prime-length loops alone still repeat per layer);
> correlation-adaptive crossfades; lossy (Opus/AAC) shipped assets; int16 in-RAM stems;
> denormal flushing; a master limiter and loudness normalisation; a time-based (not sample-based)
> budget that survives sample-rate changes; pause on headphone disconnect; no health claims;
> miniaudio on every platform; and a smaller, platform-at-a-time roadmap.

## 1. Executive Summary & Core Vision

### Product Goal
Build a cross-platform application (iOS, Android, Desktop, and optional Web PWA) that generates ambient tones, colored noise, and natural soundscapes for sleep, focus, and relaxation. Unlike traditional sleep apps that loop static 30-to-60-second audio tracks, this application will support **any arbitrary user-defined duration** (from minutes to multi-day continuous playback) while ensuring **zero perceptible repetition** or boundary artifacts.

### Core Technical Pillars
1. **Portable C++20 Real-Time DSP Core:** Write the entire sound synthesis, granular extension, and mixing engine once in lock-free, SIMD-accelerated C++20 for deterministic performance and ultra-low battery draw across all platforms.
2. **Zero-Loop Mathematical Synthesis:** Real-time procedural generation of colored noise, harmonic drones, and binaural beats directly inside the audio callback thread.
3. **Non-Linear Recorded Audio Extension:** Asynchronous multi-layer phasing, granular synthesis, and spectral seam matching so short field recordings evolve organically without ever repeating identically.
4. **Sample-Accurate Arbitrary Duration:** Hardware-clocked sample counting paired with psychoacoustic fade-out curves that prevent sudden-silence sleep disruptions.

---

## 2. Cross-Platform C++ System Architecture

To achieve glitch-free background playback and minimal battery consumption while a device screen is locked, the system separates a **Real-Time C++20 Audio Engine (`libambientsynth`)** from the **Platform Audio Drivers** and the **UI Layer**.

```
+-------------------------------------------------------------------+
|                        Cross-Platform UI Layer                    |
|        (Flutter / React Native / SwiftUI / Jetpack Compose)       |
+---------------------------------+---------------------------------+
                                  |  Control Messages (FFI / JSI)
                                  v
+-------------------------------------------------------------------+
|                     Flat C ABI Boundary (ambient_engine.h)        |
|        Lock-Free SPSC Command Queue & Atomic Parameter State      |
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                Core C++20 DSP Engine (libambientsynth)            |
|  - Colored Noise & IIR Filters   - Async Multi-Stem Player        |
|  - Detuned Drones & Binaural     - Granular & Poisson Schedulers  |
|  - STFT Spectral Seam Analyzer   - Sample-Accurate Master Clock   |
+-------+-------------------+-------------------+-------------------+
        |                   |                   |                   |
        v                   v                   v                   v
+---------------+   +---------------+   +---------------+   +---------------+
|  iOS / macOS  |   |    Android    |   |  Win / Linux  |   |   Web / PWA   |
| AVAudioEngine |   |  Google Oboe  |   |   miniaudio   |   |  Emscripten   |
| (SourceNode)  |   |   (AAudio)    |   |   (WASAPI)    |   | (AudioWorklet)|
+---------------+   +---------------+   +---------------+   +---------------+
```

### 2.1 Core C++20 Engine Design Principles (`libambientsynth`)
* **Strict Real-Time Thread Safety:** Inside the `renderBlock(float* outputBuffer, int32_t numFrames)` audio callback, enforce zero heap allocations (`new`/`malloc`), zero mutexes/locks, zero file/network I/O, and zero C++ exceptions.
* **Lock-Free UI-to-Audio Communication:** Use a Single-Producer Single-Consumer (SPSC) lock-free ring buffer (e.g., `moodycamel::ReaderWriterQueue`) for discrete commands (load audio stem, start/stop timer) and `std::atomic<float>` with parameter smoothing (one-pole low-pass) for continuous sliders (volume, filter cutoff, stereo pan) to prevent zipper noise.
* **SIMD Optimization:** Utilize ARM NEON (mobile/Apple Silicon) and x86 SSE/AVX intrinsics (or a lightweight SIMD wrapper like `xsimd`) for multi-stem mixing, equal-power crossfades, and biquad filter banks to maximize overnight battery life.
* **Denormal Safety:** Set flush-to-zero / denormals-are-zero (FTZ/DAZ) on the render thread at the start of every callback. IIR filters, the brown-noise integrator and fade-outs all decay towards zero, and denormal arithmetic causes CPU spikes on x86 exactly during the overnight tail.
* **Master Bus Protection:** Every generator is normalised to a common loudness target (e.g. $-23$ LUFS integrated) at authoring time, and the summed mix passes through a soft limiter before output, so stacking four layers at full volume can never clip. The session screen sets the engine to full scale and uses the device volume as the only loudness control. White and pink share one level; brown sits about 9 dB above that so it matches them by ear and stays clean on a phone speaker. `ambient_play` still defaults to 0.5.
* **Lightweight Audio & FFT Dependencies:**
  * **Audio Decoding:** Single-header `dr_wav` and `dr_flac` libraries for zero-dependency PCM/FLAC decoding on a background worker thread.
  * **Spectral Analysis:** `PFFFT` or `KissFFT` (C/C++) for fast offline Short-Time Fourier Transform (STFT) seam detection.

### 2.2 Platform Hardware Abstraction Layer (HAL)
Each platform hosts a thin native wrapper that opens the hardware audio stream and invokes `ambient_engine_render(...)` on the OS real-time audio thread.

**Revision:** `miniaudio` already supports CoreAudio (iOS/macOS) and AAudio/OpenSL (Android), so the default is **one miniaudio-based device layer everywhere**. Platform-native code is limited to what miniaudio does not do: the iOS `AVAudioSession` category/interruption handling and the Android foreground service and audio focus. The AVAudioEngine and Oboe paths below are fallbacks if miniaudio shows problems on a specific device.

* **iOS & macOS:** Objective-C++ wrapper (`AudioBridge.mm`) using `AVAudioEngine` with an `AVAudioSourceNode` render block, integrated with `AVAudioSessionCategoryPlayback` for lock-screen background execution.
* **Android:** Native C++ integration using **Google Oboe** (backed by `AAudio` on modern Android devices), completely bypassing the JVM and garbage collector during audio rendering.
* **Desktop (Windows / Linux):** Single-header `miniaudio` C/C++ backend targeting WASAPI (Windows) and ALSA/PulseAudio (Linux).
* **Web / PWA (Optional Demo or Companion):** Compile `libambientsynth` to **WebAssembly (WASM)** via Emscripten and execute inside a Web Audio `AudioWorkletProcessor`.

### 2.3 C ABI & UI Layer Strategy
* Expose a clean `extern "C"` interface (`ambient_engine.h`) so any UI framework can bind to the C++ core without complex marshaling:
  * **Recommended UI Stack:** **Flutter** (using `dart:ffi` for direct zero-overhead calls into C++) or **React Native** (using C++ JSI TurboModules). Both allow sharing a single UI codebase across iOS and Android while keeping $100\%$ of audio processing in native C++.
  * **Alternative All-C++ Option:** **JUCE** can be used if you also plan to release desktop audio plugins (VST3/AU), though a custom C++20 core paired with Flutter/Native UI yields a smaller binary size, modern mobile animations, and lower idle power draw.

### 2.4 Proposed Monorepo Structure
```text
/ambient-sound-app
  /core-cpp                  # Platform-agnostic C++20 DSP library
    /include/ambient_engine.h  # Public C ABI header
    /src/dsp/                  # Noise, oscillators, biquads, granular, crossfader
    /src/analysis/             # STFT spectral seam detector
    /src/engine/               # Master sample clock, voice mixer, lock-free queues
    /third_party/              # dr_wav, dr_flac, kissfft, readerwriterqueue
    CMakeLists.txt             # Cross-platform CMake build configuration
  /platform-audio            # Thin OS real-time audio drivers
    /ios-macos/                # AVAudioEngine + AVAudioSourceNode (Obj-C++)
    /android/                  # Google Oboe C++ stream callback + JNI lifecycle
    /desktop/                  # miniaudio CLI/desktop harness for rapid DSP testing
    /wasm/                     # Emscripten + AudioWorklet wrapper
  /app-ui                    # Cross-platform mobile/desktop UI (Flutter via dart:ffi)
```

### 2.5 Audio Asset Format Standards
* **Source Masters:** Uncompressed **PCM (`.wav`)** or lossless **FLAC (`.flac`)** at $f_s = 48\text{ kHz}$, $24\text{-bit}$. Kept in the asset pipeline, not shipped.
* **Shipped Assets:** **Opus** (or AAC where Opus decoding is unavailable). Encoder padding is irrelevant because stems are decoded fully into RAM and the engine chooses its own crossfade points inside the decoded buffer; the platform player never loops the file. Shipping 15 multi-stem soundscapes as FLAC would cost several hundred MB.
* **User Recordings:** Stored as FLAC on device (they are the user's only copy).
* **In-RAM Format:** Decoded stems are held as **interleaved `int16`**, converted to float on read. A stereo $48\text{ kHz}$ float32 stem of $68\text{ s}$ is $\approx 26\text{ MB}$; four 4-stem soundscapes in float32 would be $\approx 400\text{ MB}$, which iOS will terminate in the background. Long stems ($> 2\text{ min}$) stream-decode into a ring buffer on a worker thread instead.

---

## 3. Core Audio Engine Design (The "Infinite" DSP Pipeline)

### 3.1 Engine A: Procedural Synthesis (Infinite by Definition)
Procedural sounds compute each audio sample mathematically in real time inside C++, requiring zero audio storage and never repeating.

* **Colored Noise Generator:**
  * **White Noise:** Fast Xoshiro256** PRNG ($x[n] \in [-1.0, 1.0]$) with flat spectral density ($0\text{ dB/octave}$).
  * **Pink Noise ($-3\text{ dB/octave}$):** Pass white noise through a Paul Kellet multi-pole IIR filter bank to mimic steady rainfall and wind.
  * **Brownian / Red Noise ($-6\text{ dB/octave}$):** Integrate white noise via a leaky integrator ($y[n] = \alpha \cdot y[n-1] + (1 - \alpha) \cdot x[n]$) for deep waterfall and thunder rumbles.
* **Evolving Harmonic Drones:**
  * Sum $3$ to $6$ sine/triangle oscillators tuned to consonant intervals (root, fifth, octave) with slight pitch detuning ($\pm 1.5\text{ cents}$ to $\pm 4\text{ cents}$) to produce slow acoustic beating.
  * Modulate low-pass filter cutoff frequencies and stereo panning using ultra-slow, non-synchronized LFOs (periods of $37\text{ s}$, $61\text{ s}$, and $97\text{ s}$).
* **Binaural & Isochronic Tones** (offered as a sound preference; the app makes **no** sleep, health or brainwave-entrainment claims — the evidence is weak and such claims invite App Store and FTC scrutiny):
  * **Binaural Beats:** Output $f_{\text{left}} = 180\text{ Hz}$ and $f_{\text{right}} = 184\text{ Hz}$ for a perceived $4\text{ Hz}$ beat (headphone mode).
  * **Isochronic Tones:** Amplitude-modulate a carrier tone with a smooth raised-cosine envelope at the beat frequency (speaker-safe mode).

### 3.2 Engine B: Non-Linear Recorded Audio Extension
When playing real-world field recordings (rain, ocean waves, forest, fireplace) or user-imported recordings, apply four complementary C++ DSP strategies:

#### 1. Asynchronous Multi-Layer Phasing
Decompose each soundscape into $3$ to $5$ independent frequency/textural stems decoded into RAM as `float32` buffers, and loop each stem at **incommensurable (non-divisible / prime-ratio) durations**:
* **Layer 1 (Sub/Low Bed):** $29.3\text{ s}$ continuous rumble/water floor.
* **Layer 2 (Mid Texture):** $41.7\text{ s}$ steady rain/wind body.
* **Layer 3 (High Detail):** $53.1\text{ s}$ fine surface droplets/leaves.
* **Layer 4 (Stereo Ambience):** $67.9\text{ s}$ wide room/forest air.

Because the least common multiple of these lengths spans dozens of hours, the layers continuously shift phase relative to one another and never align identically during a sleep session.

**This alone is not enough.** The LCM only prevents the *whole mix* from repeating. Listeners detect repetition of a *single* layer — a memorable droplet pattern in the 53 s high-detail layer is heard every 53 s regardless of the other layers. So each layer is **not** a fixed loop: every pass plays a randomly chosen segment (random start offset, random length within $\pm 15\%$ of the nominal period, never the same start twice within the last $N$ passes), joined by the crossfade below. The nominal prime-ratio periods are kept so that layer boundaries still never coincide.

#### 2. Equal-Power Crossfading
Every individual loop boundary must overlap by $T_{\text{fade}} \in [1.5\text{ s}, 4.0\text{ s}]$ using **equal-power trigonometric curves** rather than linear fades (which cause a $-6\text{ dB}$ perceived volume dip on uncorrelated noise). For normalized crossfade progress $u \in [0, 1]$:

$$g_{\text{fade-out}}(u) = \cos\left(\frac{\pi}{2} u\right)$$

$$g_{\text{fade-in}}(u) = \sin\left(\frac{\pi}{2} u\right)$$

This guarantees constant acoustic power across the seam **only when the two signals are uncorrelated**:

$$g_{\text{fade-out}}^2(u) + g_{\text{fade-in}}^2(u) = 1$$

Seams chosen by the spectral matcher (3.2.3) are deliberately *similar*, i.e. correlated, and equal-power curves then produce a bump of up to $+3\text{ dB}$. Measure the normalised correlation $\rho \in [0, 1]$ of the two signals over the crossfade window and blend between equal-power ($\rho = 0$) and equal-gain / linear ($\rho = 1$) curves, e.g. normalise the gains so that $g_a^2 + g_b^2 + 2\rho\, g_a g_b = 1$.

#### 3. Automated Spectral Seam Detection (For User Recordings)
When a user records or imports their own audio clip, run an offline background C++ worker task to locate the least detectable loop points:
1. Compute Short-Time Fourier Transform (STFT) magnitude frames across the first $25\%$ (head) and last $25\%$ (tail) of the recording.
2. Calculate the Euclidean or cosine spectral distance matrix between candidate head frames $i$ and tail frames $j$.
3. Select the pair $(t_{\text{start}}, t_{\text{end}})$ that minimizes spectral difference and RMS energy delta, then configure the equal-power crossfade across that boundary.

#### 4. Granular Synthesis & Stochastic Event Scheduling
* **Granular Cloud Engine:** For tonal pads or singing bowls, maintain a pre-allocated pool of $32$ to $64$ voice grains spawning overlapping $40\text{ ms}$ to $120\text{ ms}$ Hann-windowed grains at randomized buffer read positions with $\pm 2\text{ cents}$ pitch jitter, creating a seamless, infinite harmonic wash.
* **Stochastic One-Shot Scheduler:** Extract distinct transient events (e.g., distant thunder, owl calls, individual wood crackles) into separate micro-samples. Trigger them via a Poisson random process with randomized playback speed ($\pm 5\%$), stereo pan, low-pass filtering, and gain so the brain never detects a rhythmic pattern.

---

## 4. Arbitrary Duration & Sleep-Safe Playback System

### 4.1 Sample-Accurate Master Clock
Never rely on UI-thread timers (`setTimeout`, `Timer`, or system wall-clock polling) to stop playback, as mobile OS power-saving modes throttle UI threads and cause drift.
* The budget is kept in **time**, counted by rendered samples: each callback of $B$ frames at the *current* rate $f_s$ advances elapsed time by $B / f_s$ (accumulated as a 64-bit frame count per rate segment, so there is no float drift).
* This survives **sample-rate changes mid-session** (Bluetooth route changes, AirPods switching to the 16 kHz hands-free profile, the OS reopening the stream at 44.1 kHz). A naive $N_{\text{total}} = \lfloor f_s T \rfloor$ computed once at start would end early or late after such a change.
* The audio clock is the reference. DAC crystals drift $20$–$100\text{ ppm}$ against wall-clock time ($\approx 1$–$4\text{ s}$ over 10 hours); that is acceptable and is not corrected.

### 4.2 Psychoacoustic Fade-In & Fade-Out Curves
Abruptly stopping ambient noise triggers an auditory startle/arousal response in sleeping users.
* **Fade-In ($3\text{ s}$ to $10\text{ s}$):** Smooth S-curve ramp from $-\infty\text{ dB}$ to target volume.
* **Fade-Out (Configurable $30\text{ s}$ to $180\text{ s}$ prior to $N_{\text{remaining}} = 0$):** Apply a logarithmic / raised-cosine attenuation curve so perceived loudness drops smoothly into the room's natural noise floor before signaling the platform audio driver to close the stream.

### 4.3 Background Execution & Interruptions
* Configure native background audio sessions (`AVAudioSessionCategoryPlayback` on iOS; Foreground Service with `MEDIA_PLAYBACK` type on Android).
* Handle phone calls and notifications gracefully inside the native audio bridge with smooth $500\text{ ms}$ ducking/fading rather than hard cuts.
* On **headphone / Bluetooth disconnect, pause** (platform convention on iOS and Android), so playback never moves to the phone speaker at 3 a.m. Resume only on explicit user action.
* Release audio hardware resources immediately once $N_{\text{remaining}} \le 0$ so the device enters deep idle sleep.

---

## 5. User Experience (UX) & Product Features

### Key Screens & Workflows
1. **Precision Arbitrary Timer:**
   * Custom wheel/keypad input allowing *any* exact duration (e.g., `00h 43m 15s` or `09h 12m 00s`), alongside quick-tap presets.
   * Configurable **Sleep Fade-Out Window** (e.g., fade over the final $1\text{ min}$, $5\text{ min}$, or $15\text{ min}$).
2. **Soundscape Mixer & Layering:**
   * Combine up to $4$ simultaneous generators (e.g., *Brown Noise* + *Async Rain Bed* + *Stochastic Distant Thunder* + *4 Hz Binaural Theta Drone*).
   * Individual volume sliders, tone/warmth (low-pass filter) knobs, and stereo width controls per layer.
3. **"Capture & Extend" Custom Loop Studio:**
   * In-app microphone recorder or file importer.
   * One-tap **Make Infinite** processing: runs the C++ STFT spectral seam matcher, generates multi-pitch asynchronous layers, and saves the result as an infinite custom preset.
4. **Sleep-Safe Interface:**
   * True-black OLED dark mode with dimmable warm-amber accents (zero blue-light emission).
   * Optional auto-dimming lock screen after $15\text{ seconds}$ of inactivity.

---

## 6. Phased Development Roadmap (C++ First, One Platform at a Time)

The first draft fit a C++ core, four platform drivers, granular synthesis, an STFT analyser, a Flutter UI and a 15-soundscape library into 14 weeks. That is not realistic, and the sound library alone is a sound-design project. Each phase below ends in something shippable.

### Phase 1: Procedural Core & Desktop Harness
* CMake project for `libambientsynth`, the flat C ABI, and a `miniaudio` desktop player.
* White/pink/brown noise, smoothed parameters, master limiter, FTZ/DAZ, time-based timer with S-curve fade-in and raised-cosine fade-out.
* Unit tests (spectral slope, timer accuracy, determinism, fade-out ends in silence) in CI.
* **Milestone:** 8+ hours of glitch-free procedural audio on desktop, $< 2\%$ of one core, no render-thread allocations.

### Phase 2: First Mobile Release (iOS *or* Android, procedural only)
* miniaudio device layer + native audio-session / foreground-service glue.
* Minimal UI: generator picker, per-layer volume and tone, arbitrary-duration timer, fade-out window. Drones and binaural/isochronic tones.
* **Milestone:** lock the screen with a `1h 37m` timer and hear seamless playback until the fade completes. Ship it.

### Phase 3: Recorded Soundscapes (Engine B)
* Opus decoding to int16, randomised-segment stem player, correlation-adaptive crossfades, Poisson one-shot scheduler.
* Produce the first 3–4 soundscapes properly (recording/licensing, stem separation, loudness normalisation) before building more.
* **Milestone:** a 30 s rain + thunder stem pack plays for 2 hours with zero audible seams or recognisable repetition (blind test).

### Phase 4: Second Platform, Capture & Extend, Library
* Port to the other mobile platform (and optionally the web: a plain JS `AudioWorklet` is enough for procedural sound; WASM only once Engine B is needed there).
* Offline STFT seam matcher + "Make Infinite" for user recordings; granular voice pool.
* Grow the library towards 12–15 soundscapes.

---

## 7. Quality Assurance & Psychoacoustic Verification

* **Real-Time Safety Verification:** Run AddressSanitizer (`ASan`) and custom allocation-hook tests on `renderBlock(...)` to verify zero heap allocations, locks, or priority inversions during playback.
* **Blind Loop-Detection Test:** Have testers listen on studio headphones for $20\text{ minutes}$ to a $25\text{-second}$ source recording processed by the engine and mark timestamps whenever they perceive a repeat or seam. Target: $0\%$ seam detection and $< 5\%$ false-positive pattern detection.
* **Overnight Thermal & Battery Benchmark:** Run a $10\text{-hour}$ session on mid-tier iOS and Android devices in airplane/lock mode; verify $< 10\%$ overnight battery drain and zero buffer underruns (clicks/pops).
* **Timer Accuracy Audit:** Verify that a requested duration of $T$ seconds terminates within $\pm 1\text{ audio buffer}$ of $T$ measured in **rendered audio time** (including across a forced sample-rate change). Wall-clock comparison is reported but not a pass/fail criterion, because DAC drift ($20$–$100\text{ ppm}$) exceeds the target over long sessions.
* **Loudness & Clipping:** Every shipped soundscape measures within $\pm 1\text{ LU}$ of the target; four layers at maximum volume never exceed $-1\text{ dBFS}$ true peak after the limiter.