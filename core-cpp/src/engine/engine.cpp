// libhumspansynth engine: procedural noise, smoothed parameters, a timer kept
// in rendered audio time, psychoacoustic fades and a soft output clipper.
#include "humspan_engine.h"

#include "denormals.hpp"
#include "dsp/noise.hpp"
#include "dsp/tone.hpp"
#include "spsc_queue.hpp"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>
#include <numbers>

namespace {

using humspan::dsp::BrownFilter;
using humspan::dsp::kWhiteGain;
using humspan::dsp::PinkFilter;
using humspan::dsp::ResonantBoom;
using humspan::dsp::SineOscillator;
using humspan::dsp::Xoshiro256;

constexpr int kColorCount = 3;
constexpr double kSmoothingSeconds = 0.03; // parameter smoothing time constant
constexpr double kDuckSeconds = 0.1;       // duck time constant: settles in ~500 ms
constexpr float kSilent = 1e-6f;

// Binaural beat: a fixed carrier in the left ear, carrier + beat in the right.
constexpr double kCarrierHz = 180.0;
constexpr float kMinBeatHz = 1.0f;
constexpr float kMaxBeatHz = 30.0f;
constexpr float kBinauralMix = 0.5f; // -6 dB under the noise
constexpr float kMinBoomSeconds = 1.0f;
constexpr float kMaxBoomSeconds = 16.0f;
constexpr float kDefaultBoomSeconds = 8.0f;

struct Command {
    enum class Type { Start, Stop, Pause, Resume } type;
    double duration;
    double fadeIn;  // Resume: the resume fade
    double fadeOut; // Stop, Pause: their fade
};

// Raised-cosine S-curve on [0, 1].
inline double sCurve(double u) {
    u = std::clamp(u, 0.0, 1.0);
    return 0.5 - 0.5 * std::cos(std::numbers::pi * u);
}

// Fade-out shape: squared raised cosine. Spends more of the fade at low
// levels than a plain cosine, so loudness sinks smoothly into the room's
// noise floor, and reaches exact zero.
inline double fadeOutCurve(double u) {
    const double c = 1.0 - sCurve(u);
    return c * c;
}

// Transparent below -2 dBFS, then a tanh knee that can never reach 1.0.
inline float softClip(float x) {
    constexpr float kKnee = 0.8f;
    const float a = std::fabs(x);
    if (a <= kKnee) {
        return x;
    }
    const float y = kKnee + (1.0f - kKnee) * std::tanh((a - kKnee) / (1.0f - kKnee));
    return std::copysign(y, x);
}

// Linear through the bed. Only the hottest peaks round off, so brown stays
// clean and a strike still has room beside it.
inline float holdBed(float x) {
    constexpr float kKnee = 0.70f;
    constexpr float kLimit = 0.85f;
    const float a = std::fabs(x);
    if (a <= kKnee) {
        return x;
    }
    const float span = kLimit - kKnee;
    const float y = kKnee + span * std::tanh((a - kKnee) / span);
    return std::copysign(y, x);
}

struct Channel {
    Xoshiro256 rng;
    PinkFilter pink;
    BrownFilter brown;
};

} // namespace

struct humspan_engine {
    // ---- control -> audio ----
    humspan::engine::SpscQueue<Command, 16> commands;
    std::atomic<int> color{HUMSPAN_NOISE_PINK};
    std::atomic<bool> noise{true};
    std::atomic<float> noiseLevel{1.0f};
    std::atomic<float> binauralLevel{1.0f};
    std::atomic<float> boomLevel{1.0f};
    std::atomic<float> volume{0.5f};
    std::atomic<float> duck{1.0f};
    std::atomic<bool> binaural{false};
    std::atomic<float> beatHz{4.0f};
    std::atomic<bool> boom{false};
    std::atomic<float> boomInterval{kDefaultBoomSeconds};

    // ---- audio -> control ----
    std::atomic<double> elapsedReport{0.0};
    std::atomic<double> remainingReport{0.0};
    std::atomic<bool> playingReport{false};
    std::atomic<bool> pausedReport{false};

    // ---- audio thread state ----
    double rate = 48000.0;
    double invRate = 1.0 / 48000.0;
    float smoothCoeff = 0.0f;
    float duckCoeff = 0.0f;

    Channel channels[2];
    float colorGain[kColorCount] = {0.0f, 0.0f, 0.0f};
    float smoothedVolume = 0.5f;
    float smoothedDuck = 1.0f;
    float noiseGain = 1.0f;       // noise on/off, smoothed
    float smoothedNoiseLevel = 1.0f;
    float binauralGain = 0.0f;    // on/off x kBinauralMix x level, smoothed
    float boomGain = 0.0f;        // on/off x level, smoothed
    SineOscillator tones[2]; // left: carrier, right: carrier + beat
    ResonantBoom resonator;

    bool active = false;
    bool snapGains = false;     // set by a Start from idle, applied in render
    double elapsedBase = 0.0;   // seconds rendered before the current rate segment
    int64_t segmentFrames = 0;  // frames rendered at the current rate
    double duration = 0.0;      // <= 0: until stopped
    double fadeIn = 0.0;
    double fadeOut = 0.0;
    double startLevel = 0.0;    // envelope level when the session (re)started
    double envelope = 0.0;      // last rendered envelope level

    bool stopping = false;
    double stopAt = 0.0;
    double stopLevel = 0.0;
    double stopFade = 0.0;

    // Pause/resume: a hold gain multiplies the session envelope. Once a pause
    // fade reaches zero the session is paused and its timer stops.
    bool paused = false;
    bool holdRamping = false;
    double holdLevel = 1.0;  // last hold gain
    double holdFrom = 1.0;   // hold gain when the current ramp began
    double holdTarget = 1.0; // 0: pausing, 1: resuming
    double holdAt = 0.0;
    double holdFade = 0.0;

    void applyRate(double newRate) {
        rate = newRate;
        invRate = 1.0 / newRate;
        smoothCoeff = static_cast<float>(1.0 - std::exp(-1.0 / (kSmoothingSeconds * newRate)));
        duckCoeff = static_cast<float>(1.0 - std::exp(-1.0 / (kDuckSeconds * newRate)));
        for (auto& ch : channels) {
            ch.brown.setSampleRate(newRate);
        }
        resonator.setSampleRate(newRate);
    }

    double now(int64_t extraFrames = 0) const {
        return elapsedBase + static_cast<double>(segmentFrames + extraFrames) * invRate;
    }

    void handle(const Command& cmd) {
        switch (cmd.type) {
        case Command::Type::Start:
            // From idle nothing is sounding, so the smoothed gains can jump
            // to their targets: the session opens on the chosen mix.
            snapGains = !active;
            startLevel = active ? envelope : 0.0;
            active = true;
            stopping = false;
            paused = false;
            holdRamping = false;
            holdLevel = 1.0;
            holdTarget = 1.0;
            elapsedBase = 0.0;
            segmentFrames = 0;
            duration = cmd.duration > 0.0 ? cmd.duration : 0.0;
            fadeIn = std::max(cmd.fadeIn, 0.0);
            fadeOut = std::max(cmd.fadeOut, 0.0);
            // Too short for both fades: shrink them in proportion to fit.
            if (duration > 0.0 && fadeIn + fadeOut > duration) {
                const double scale = duration / (fadeIn + fadeOut);
                fadeIn *= scale;
                fadeOut *= scale;
            }
            break;
        case Command::Type::Stop:
            if (paused) { // already silent: finish at once
                active = false;
                paused = false;
            } else if (active && !stopping) {
                stopping = true;
                stopAt = now();
                stopLevel = envelope;
                stopFade = std::max(cmd.fadeOut, invRate);
            }
            break;
        case Command::Type::Pause:
            if (active && !paused && !stopping) {
                beginHoldRamp(0.0, cmd.fadeOut);
            }
            break;
        case Command::Type::Resume:
            if (active && !stopping && (paused || holdTarget == 0.0)) {
                paused = false;
                beginHoldRamp(1.0, cmd.fadeIn);
            }
            break;
        }
    }

    void beginHoldRamp(double target, double fade) {
        holdFrom = holdLevel;
        holdTarget = target;
        holdAt = now();
        holdFade = std::max(fade, invRate);
        holdRamping = true;
    }

    // Hold gain at session time t; sets paused=true when a pause completes.
    double holdGainAt(double t) {
        if (!holdRamping) {
            return holdLevel;
        }
        const double u = (t - holdAt) / holdFade;
        if (u >= 1.0) {
            holdRamping = false;
            holdLevel = holdTarget;
            if (holdTarget == 0.0) {
                // Silent now. A stop that arrived mid-fade finishes here
                // rather than pausing (its timer would never run out).
                paused = !stopping;
                active = !stopping;
            }
        } else if (holdTarget == 0.0) {
            holdLevel = holdFrom * fadeOutCurve(u);
        } else {
            holdLevel = holdFrom + (1.0 - holdFrom) * sCurve(u);
        }
        return holdLevel;
    }

    // Envelope at session time t; sets active=false when the session ends.
    double envelopeAt(double t) {
        if (duration > 0.0 && t >= duration) {
            active = false;
            return 0.0;
        }
        double g = fadeIn > 0.0 ? startLevel + (1.0 - startLevel) * sCurve(t / fadeIn) : 1.0;
        if (duration > 0.0 && fadeOut > 0.0) {
            const double fadeStart = duration - fadeOut;
            if (t > fadeStart) {
                g = std::min(g, fadeOutCurve((t - fadeStart) / fadeOut));
            }
        }
        g *= holdGainAt(t);
        if (stopping) {
            const double u = (t - stopAt) / stopFade;
            if (u >= 1.0) {
                active = false;
                return 0.0;
            }
            g = std::min(g, stopLevel * fadeOutCurve(u));
        }
        return g;
    }

    int render(float* out, int32_t frames) {
        humspan::engine::ScopedFlushDenormals ftz;

        while (auto cmd = commands.pop()) {
            handle(*cmd);
        }

        const int targetColor = color.load(std::memory_order_relaxed);
        const float targetVolume = volume.load(std::memory_order_relaxed);
        const float targetDuck = duck.load(std::memory_order_relaxed);
        const bool noiseOn = noise.load(std::memory_order_relaxed);
        const float targetNoiseLevel = noiseLevel.load(std::memory_order_relaxed);
        const bool binauralOn = binaural.load(std::memory_order_relaxed);
        const float targetBinaural =
            binauralOn ? kBinauralMix * binauralLevel.load(std::memory_order_relaxed) : 0.0f;
        const bool boomOn = boom.load(std::memory_order_relaxed);
        const float targetBoom = boomOn ? boomLevel.load(std::memory_order_relaxed) : 0.0f;
        const double boomEvery = static_cast<double>(boomInterval.load(std::memory_order_relaxed));
        if (snapGains) {
            snapGains = false;
            smoothedVolume = targetVolume;
            smoothedDuck = targetDuck;
            for (int c = 0; c < kColorCount; ++c) {
                colorGain[c] = c == targetColor ? 1.0f : 0.0f;
            }
            noiseGain = noiseOn ? 1.0f : 0.0f;
            smoothedNoiseLevel = targetNoiseLevel;
            binauralGain = targetBinaural;
            boomGain = targetBoom;
        }
        const double toneStep[2] = {
            kCarrierHz * invRate,
            (kCarrierHz + static_cast<double>(beatHz.load(std::memory_order_relaxed))) * invRate,
        };

        for (int32_t n = 0; n < frames; ++n) {
            if (!active || paused) { // paused: silent, timer held
                envelope = 0.0;
                out[2 * n] = 0.0f;
                out[2 * n + 1] = 0.0f;
                continue;
            }

            const double env = envelopeAt(now());
            envelope = env;
            if (!active || paused) { // finished or paused exactly at this frame
                out[2 * n] = 0.0f;
                out[2 * n + 1] = 0.0f;
                continue;
            }
            ++segmentFrames;

            smoothedVolume += smoothCoeff * (targetVolume - smoothedVolume);
            smoothedDuck += duckCoeff * (targetDuck - smoothedDuck);
            for (int c = 0; c < kColorCount; ++c) {
                const float target = c == targetColor ? 1.0f : 0.0f;
                colorGain[c] += smoothCoeff * (target - colorGain[c]);
            }
            noiseGain += smoothCoeff * ((noiseOn ? 1.0f : 0.0f) - noiseGain);
            smoothedNoiseLevel += smoothCoeff * (targetNoiseLevel - smoothedNoiseLevel);
            binauralGain += smoothCoeff * (targetBinaural - binauralGain);
            boomGain += smoothCoeff * (targetBoom - boomGain);
            // Noise filters keep running while audible or fading in; skipped
            // only once the layer is off and fully silent.
            const bool noiseAudible = noiseGain > kSilent || noiseOn;
            const bool toneAudible = binauralGain > kSilent || binauralOn;
            const bool boomAudible = boomGain > kSilent || boomOn;
            if (boomAudible) resonator.arm();
            else resonator.reset();
            const float gain = smoothedVolume * smoothedDuck * static_cast<float>(env);

            for (int ch = 0; ch < 2; ++ch) {
                Channel& chan = channels[ch];
                // The generator always advances, so the noise stream (and
                // determinism) does not depend on when noise was switched.
                const float white = chan.rng.bipolar();
                float bed = 0.0f;
                if (noiseAudible) {
                    if (colorGain[HUMSPAN_NOISE_WHITE] > kSilent) {
                        bed += colorGain[HUMSPAN_NOISE_WHITE] * white * kWhiteGain;
                    }
                    // Filters keep running while audible or fading in; skipped
                    // only when fully silent (their state then fades in from 0).
                    if (colorGain[HUMSPAN_NOISE_PINK] > kSilent || targetColor == HUMSPAN_NOISE_PINK) {
                        bed += colorGain[HUMSPAN_NOISE_PINK] * chan.pink.process(white);
                    }
                    if (colorGain[HUMSPAN_NOISE_BROWN] > kSilent || targetColor == HUMSPAN_NOISE_BROWN) {
                        bed += colorGain[HUMSPAN_NOISE_BROWN] * chan.brown.process(white);
                    }
                    bed *= noiseGain * smoothedNoiseLevel;
                }
                float layer = 0.0f;
                if (toneAudible) {
                    layer += binauralGain * tones[ch].process(toneStep[ch]);
                }
                if (boomAudible) {
                    layer += boomGain * resonator.sample(ch);
                }
                out[2 * n + ch] = softClip(holdBed(bed * gain) + layer * gain);
            }
            if (boomAudible) resonator.advance(boomEvery);
        }

        const double elapsed = active ? now() : 0.0;
        double remaining = 0.0;
        if (active) {
            remaining = duration > 0.0 ? std::max(duration - elapsed, 0.0) : -1.0;
        }
        elapsedReport.store(elapsed, std::memory_order_relaxed);
        remainingReport.store(remaining, std::memory_order_relaxed);
        playingReport.store(active, std::memory_order_relaxed);
        pausedReport.store(active && paused, std::memory_order_relaxed);
        return active ? 1 : 0;
    }
};

extern "C" {

humspan_engine* humspan_engine_create(uint32_t sample_rate, uint64_t seed) {
    if (sample_rate == 0) {
        return nullptr;
    }
    auto* engine = new (std::nothrow) humspan_engine();
    if (engine == nullptr) {
        return nullptr;
    }
    engine->channels[0].rng.reseed(seed);
    engine->channels[1].rng.reseed(seed ^ 0xA5A5A5A5DEADBEEFull);
    engine->applyRate(static_cast<double>(sample_rate));
    engine->colorGain[HUMSPAN_NOISE_PINK] = 1.0f;
    return engine;
}

void humspan_engine_destroy(humspan_engine* engine) { delete engine; }

void humspan_engine_set_sample_rate(humspan_engine* engine, uint32_t sample_rate) {
    if (engine == nullptr || sample_rate == 0) {
        return;
    }
    // Fold the finished segment into seconds so the session timer is kept in
    // time and the remaining duration survives the change.
    engine->elapsedBase = engine->now();
    engine->segmentFrames = 0;
    engine->applyRate(static_cast<double>(sample_rate));
}

void humspan_engine_set_noise_color(humspan_engine* engine, humspan_noise_color color) {
    if (engine != nullptr && color >= HUMSPAN_NOISE_WHITE && color <= HUMSPAN_NOISE_BROWN) {
        engine->color.store(color, std::memory_order_relaxed);
    }
}

void humspan_engine_set_noise(humspan_engine* engine, int enabled) {
    if (engine != nullptr) {
        engine->noise.store(enabled != 0, std::memory_order_relaxed);
    }
}

namespace {
void storeLevel(std::atomic<float>& level, float value) {
    if (!std::isnan(value)) {
        level.store(std::clamp(value, 0.0f, 1.0f), std::memory_order_relaxed);
    }
}
} // namespace

void humspan_engine_set_noise_level(humspan_engine* engine, float level) {
    if (engine != nullptr) storeLevel(engine->noiseLevel, level);
}

void humspan_engine_set_binaural_level(humspan_engine* engine, float level) {
    if (engine != nullptr) storeLevel(engine->binauralLevel, level);
}

void humspan_engine_set_boom_level(humspan_engine* engine, float level) {
    if (engine != nullptr) storeLevel(engine->boomLevel, level);
}

void humspan_engine_set_volume(humspan_engine* engine, float volume) {
    if (engine != nullptr && !std::isnan(volume)) {
        engine->volume.store(std::clamp(volume, 0.0f, 1.0f), std::memory_order_relaxed);
    }
}

void humspan_engine_set_duck_gain(humspan_engine* engine, float gain) {
    if (engine != nullptr && !std::isnan(gain)) {
        engine->duck.store(std::clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
    }
}

void humspan_engine_set_binaural(humspan_engine* engine, int enabled) {
    if (engine != nullptr) {
        engine->binaural.store(enabled != 0, std::memory_order_relaxed);
    }
}

void humspan_engine_set_beat_frequency(humspan_engine* engine, float beat_hz) {
    if (engine != nullptr && !std::isnan(beat_hz)) {
        engine->beatHz.store(std::clamp(beat_hz, kMinBeatHz, kMaxBeatHz), std::memory_order_relaxed);
    }
}

void humspan_engine_set_boom(humspan_engine* engine, int enabled) {
    if (engine != nullptr) {
        engine->boom.store(enabled != 0, std::memory_order_relaxed);
    }
}

void humspan_engine_set_boom_interval(humspan_engine* engine, float seconds) {
    if (engine != nullptr && !std::isnan(seconds)) {
        engine->boomInterval.store(std::clamp(seconds, kMinBoomSeconds, kMaxBoomSeconds),
                                    std::memory_order_relaxed);
    }
}

int humspan_engine_start(humspan_engine* engine, double duration_seconds,
                         double fade_in_seconds, double fade_out_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Start, duration_seconds, fade_in_seconds,
                                  fade_out_seconds})
               ? 1
               : 0;
}

int humspan_engine_stop(humspan_engine* engine, double fade_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Stop, 0.0, 0.0, fade_seconds}) ? 1 : 0;
}

int humspan_engine_pause(humspan_engine* engine, double fade_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Pause, 0.0, 0.0, fade_seconds}) ? 1 : 0;
}

int humspan_engine_resume(humspan_engine* engine, double fade_in_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Resume, 0.0, fade_in_seconds, 0.0}) ? 1 : 0;
}

int humspan_engine_render(humspan_engine* engine, float* out, int32_t frames) {
    if (engine == nullptr || out == nullptr || frames <= 0) {
        return 0;
    }
    return engine->render(out, frames);
}

double humspan_engine_elapsed_seconds(const humspan_engine* engine) {
    return engine != nullptr ? engine->elapsedReport.load(std::memory_order_relaxed) : 0.0;
}

double humspan_engine_remaining_seconds(const humspan_engine* engine) {
    return engine != nullptr ? engine->remainingReport.load(std::memory_order_relaxed) : 0.0;
}

int humspan_engine_is_playing(const humspan_engine* engine) {
    return engine != nullptr && engine->playingReport.load(std::memory_order_relaxed) ? 1 : 0;
}

int humspan_engine_is_paused(const humspan_engine* engine) {
    return engine != nullptr && engine->pausedReport.load(std::memory_order_relaxed) ? 1 : 0;
}

} // extern "C"
