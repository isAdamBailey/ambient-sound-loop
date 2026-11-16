// libambientsynth engine: procedural noise, smoothed parameters, a timer kept
// in rendered audio time, psychoacoustic fades and a soft output clipper.
#include "ambient_engine.h"

#include "denormals.hpp"
#include "dsp/noise.hpp"
#include "spsc_queue.hpp"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>
#include <numbers>

namespace {

using ambient::dsp::BrownFilter;
using ambient::dsp::kWhiteGain;
using ambient::dsp::PinkFilter;
using ambient::dsp::Xoshiro256;

constexpr int kColorCount = 3;
constexpr double kSmoothingSeconds = 0.03; // parameter smoothing time constant
constexpr float kSilent = 1e-6f;

struct Command {
    enum class Type { Start, Stop } type;
    double duration;
    double fadeIn;
    double fadeOut; // Stop: the stop fade
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

struct Channel {
    Xoshiro256 rng;
    PinkFilter pink;
    BrownFilter brown;
};

} // namespace

struct ambient_engine {
    // ---- control -> audio ----
    ambient::engine::SpscQueue<Command, 16> commands;
    std::atomic<int> color{AMBIENT_NOISE_PINK};
    std::atomic<float> volume{0.5f};

    // ---- audio -> control ----
    std::atomic<double> elapsedReport{0.0};
    std::atomic<bool> playingReport{false};

    // ---- audio thread state ----
    double rate = 48000.0;
    double invRate = 1.0 / 48000.0;
    float smoothCoeff = 0.0f;

    Channel channels[2];
    float colorGain[kColorCount] = {0.0f, 0.0f, 0.0f};
    float smoothedVolume = 0.5f;

    bool active = false;
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

    void applyRate(double newRate) {
        rate = newRate;
        invRate = 1.0 / newRate;
        smoothCoeff = static_cast<float>(1.0 - std::exp(-1.0 / (kSmoothingSeconds * newRate)));
        for (auto& ch : channels) {
            ch.brown.setSampleRate(newRate);
        }
    }

    double now(int64_t extraFrames = 0) const {
        return elapsedBase + static_cast<double>(segmentFrames + extraFrames) * invRate;
    }

    void handle(const Command& cmd) {
        switch (cmd.type) {
        case Command::Type::Start:
            startLevel = active ? envelope : 0.0;
            active = true;
            stopping = false;
            elapsedBase = 0.0;
            segmentFrames = 0;
            duration = cmd.duration > 0.0 ? cmd.duration : 0.0;
            fadeIn = std::max(cmd.fadeIn, 0.0);
            fadeOut = std::max(cmd.fadeOut, 0.0);
            if (duration > 0.0) {
                fadeOut = std::min(fadeOut, duration);
            }
            break;
        case Command::Type::Stop:
            if (active && !stopping) {
                stopping = true;
                stopAt = now();
                stopLevel = envelope;
                stopFade = std::max(cmd.fadeOut, invRate);
            }
            break;
        }
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
        ambient::engine::ScopedFlushDenormals ftz;

        while (auto cmd = commands.pop()) {
            handle(*cmd);
        }

        const int targetColor = color.load(std::memory_order_relaxed);
        const float targetVolume = volume.load(std::memory_order_relaxed);

        for (int32_t n = 0; n < frames; ++n) {
            if (!active) {
                envelope = 0.0;
                out[2 * n] = 0.0f;
                out[2 * n + 1] = 0.0f;
                continue;
            }

            const double env = envelopeAt(now());
            envelope = env;
            if (!active) { // finished exactly at this frame
                out[2 * n] = 0.0f;
                out[2 * n + 1] = 0.0f;
                continue;
            }
            ++segmentFrames;

            smoothedVolume += smoothCoeff * (targetVolume - smoothedVolume);
            for (int c = 0; c < kColorCount; ++c) {
                const float target = c == targetColor ? 1.0f : 0.0f;
                colorGain[c] += smoothCoeff * (target - colorGain[c]);
            }
            const float gain = smoothedVolume * static_cast<float>(env);

            for (int ch = 0; ch < 2; ++ch) {
                Channel& chan = channels[ch];
                const float white = chan.rng.bipolar();
                float mix = 0.0f;
                if (colorGain[AMBIENT_NOISE_WHITE] > kSilent) {
                    mix += colorGain[AMBIENT_NOISE_WHITE] * white * kWhiteGain;
                }
                // Filters keep running while audible or fading in; skipped
                // only when fully silent (their state then fades in from 0).
                if (colorGain[AMBIENT_NOISE_PINK] > kSilent || targetColor == AMBIENT_NOISE_PINK) {
                    mix += colorGain[AMBIENT_NOISE_PINK] * chan.pink.process(white);
                }
                if (colorGain[AMBIENT_NOISE_BROWN] > kSilent || targetColor == AMBIENT_NOISE_BROWN) {
                    mix += colorGain[AMBIENT_NOISE_BROWN] * chan.brown.process(white);
                }
                out[2 * n + ch] = softClip(mix * gain);
            }
        }

        elapsedReport.store(active ? now() : 0.0, std::memory_order_relaxed);
        playingReport.store(active, std::memory_order_relaxed);
        return active ? 1 : 0;
    }
};

extern "C" {

ambient_engine* ambient_engine_create(uint32_t sample_rate, uint64_t seed) {
    if (sample_rate == 0) {
        return nullptr;
    }
    auto* engine = new (std::nothrow) ambient_engine();
    if (engine == nullptr) {
        return nullptr;
    }
    engine->channels[0].rng.reseed(seed);
    engine->channels[1].rng.reseed(seed ^ 0xA5A5A5A5DEADBEEFull);
    engine->applyRate(static_cast<double>(sample_rate));
    engine->colorGain[AMBIENT_NOISE_PINK] = 1.0f;
    return engine;
}

void ambient_engine_destroy(ambient_engine* engine) { delete engine; }

void ambient_engine_set_sample_rate(ambient_engine* engine, uint32_t sample_rate) {
    if (engine == nullptr || sample_rate == 0) {
        return;
    }
    // Fold the finished segment into seconds so the session timer is kept in
    // time and the remaining duration survives the change.
    engine->elapsedBase = engine->now();
    engine->segmentFrames = 0;
    engine->applyRate(static_cast<double>(sample_rate));
}

void ambient_engine_set_noise_color(ambient_engine* engine, ambient_noise_color color) {
    if (engine != nullptr && color >= AMBIENT_NOISE_WHITE && color <= AMBIENT_NOISE_BROWN) {
        engine->color.store(color, std::memory_order_relaxed);
    }
}

void ambient_engine_set_volume(ambient_engine* engine, float volume) {
    if (engine != nullptr && !std::isnan(volume)) {
        engine->volume.store(std::clamp(volume, 0.0f, 1.0f), std::memory_order_relaxed);
    }
}

int ambient_engine_start(ambient_engine* engine, double duration_seconds,
                         double fade_in_seconds, double fade_out_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Start, duration_seconds, fade_in_seconds,
                                  fade_out_seconds})
               ? 1
               : 0;
}

int ambient_engine_stop(ambient_engine* engine, double fade_seconds) {
    if (engine == nullptr) {
        return 0;
    }
    return engine->commands.push({Command::Type::Stop, 0.0, 0.0, fade_seconds}) ? 1 : 0;
}

int ambient_engine_render(ambient_engine* engine, float* out, int32_t frames) {
    if (engine == nullptr || out == nullptr || frames <= 0) {
        return 0;
    }
    return engine->render(out, frames);
}

double ambient_engine_elapsed_seconds(const ambient_engine* engine) {
    return engine != nullptr ? engine->elapsedReport.load(std::memory_order_relaxed) : 0.0;
}

int ambient_engine_is_playing(const ambient_engine* engine) {
    return engine != nullptr && engine->playingReport.load(std::memory_order_relaxed) ? 1 : 0;
}

} // extern "C"
