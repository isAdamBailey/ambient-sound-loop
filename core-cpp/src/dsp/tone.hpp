// Tone generators. Header-only, allocation-free, real-time safe.
#pragma once

#include "dsp/noise.hpp"

#include <cmath>
#include <numbers>

namespace humspan::dsp {

// Phase-continuous sine, normalised to kNoiseRms like every generator.
// Changing the frequency keeps the phase, so it never clicks.
class SineOscillator {
public:
    // A sine of amplitude A has RMS A / sqrt(2).
    static constexpr float kGain = kNoiseRms * std::numbers::sqrt2_v<float>;

    // `cyclesPerSample` = frequency / sample rate.
    float process(double cyclesPerSample) noexcept {
        const float y = static_cast<float>(std::sin(2.0 * std::numbers::pi * phase_)) * kGain;
        phase_ += cyclesPerSample;
        phase_ -= std::floor(phase_);
        return y;
    }

private:
    double phase_ = 0.0; // in cycles, [0, 1)
};

// A low struck resonator. Each strike rings in one ear, then the other.
// An octave sits above the fundamental so the pitch reads on headphones.
// A new strike fades in from silence while the previous one keeps decaying,
// so the retrigger does not click.
class ResonantBoom {
public:
    static constexpr double kFrequencyHz = 52.0;
    static constexpr double kHarmonicHz = 104.0;
    static constexpr double kDecaySeconds = 1.2;
    static constexpr double kAttackSeconds = 0.04;
    static constexpr float kPeak = 0.30f;
    static constexpr float kHarmonic = 0.24f;

    void setSampleRate(double sampleRate) noexcept {
        const double rate = sampleRate > 0.0 ? sampleRate : 48000.0;
        step_ = kFrequencyHz / rate;
        harmonicStep_ = kHarmonicHz / rate;
        sampleSeconds_ = 1.0 / rate;
        decay_ = static_cast<float>(std::exp(-sampleSeconds_ / kDecaySeconds));
        attackStep_ = static_cast<float>(1.0 / (kAttackSeconds * rate));
    }

    // The first call strikes the left ear. Later strikes follow `advance`.
    void arm() noexcept {
        if (!struck_) strike();
    }

    float sample(int channel) const noexcept {
        float y = 0.0f;
        for (const auto& voice : voices_) {
            if (voice.ear != channel || voice.env <= kSilent) continue;
            const float fundamental = static_cast<float>(std::sin(2.0 * std::numbers::pi * voice.phase));
            const float harmonic = static_cast<float>(std::sin(2.0 * std::numbers::pi * voice.harmonic));
            y += (fundamental * kPeak + harmonic * kHarmonic) * voice.env * voice.attack;
        }
        return y;
    }

    // Move one sample forward. `intervalSeconds` is the gap between strikes.
    void advance(double intervalSeconds) noexcept {
        for (auto& voice : voices_) {
            voice.env *= decay_;
            if (voice.attack < 1.0f) {
                voice.attack += attackStep_;
                if (voice.attack > 1.0f) voice.attack = 1.0f;
            }
            voice.phase += step_;
            voice.phase -= std::floor(voice.phase);
            voice.harmonic += harmonicStep_;
            voice.harmonic -= std::floor(voice.harmonic);
        }
        const double interval = intervalSeconds > 1e-3 ? intervalSeconds : 1.0;
        intervalPhase_ += sampleSeconds_ / interval;
        if (intervalPhase_ >= 1.0) {
            intervalPhase_ -= std::floor(intervalPhase_);
            strike();
        }
    }

    void reset() noexcept {
        intervalPhase_ = 0.0;
        voices_[0] = {};
        voices_[1] = {};
        ear_ = 1;
        active_ = 0;
        struck_ = false;
    }

private:
    struct Voice {
        float env = 0.0f;
        float attack = 1.0f;
        double phase = 0.0;
        double harmonic = 0.0;
        int ear = 0;
    };

    void strike() noexcept {
        ear_ ^= 1;
        active_ ^= 1;
        Voice& voice = voices_[active_];
        voice.env = 1.0f;
        voice.attack = 0.0f;
        voice.phase = 0.0;
        voice.harmonic = 0.0;
        voice.ear = ear_;
        struck_ = true;
    }

    static constexpr float kSilent = 1.0e-5f;

    double step_ = 52.0 / 48000.0;
    double harmonicStep_ = 104.0 / 48000.0;
    double sampleSeconds_ = 1.0 / 48000.0;
    float decay_ = 1.0f;
    float attackStep_ = 0.0f;
    double intervalPhase_ = 0.0;
    Voice voices_[2]{};
    int ear_ = 1; // strike() flips this, so the first hit is the left ear
    int active_ = 0;
    bool struck_ = false;
};

} // namespace humspan::dsp
