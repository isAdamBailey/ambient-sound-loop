// Tone generators. Header-only, allocation-free, real-time safe.
#pragma once

#include "dsp/noise.hpp"

#include <algorithm>
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

// How a ResonantBoom sounds: the partials of its ringing tail and its strike.
struct BoomVoicing {
    static constexpr int kPartialCount = 5;
    struct Partial {
        double ratio;        // of frequencyHz
        float peak;          // amplitude at the strike
        double decaySeconds; // exponential time constant
    };
    double frequencyHz;
    Partial partials[kPartialCount];
    double dropRatio;     // a strike starts this much sharp
    double dropSeconds;   // and falls to pitch with this time constant
    float thump;          // peak of the beater's noise burst
    double thumpSeconds;
    double thumpHz;       // low-pass corner of the burst
    double thumpFloorHz;  // high-pass corner of the burst, 0 for none
    double attackSeconds; // rise of each strike
};

// Headphones: a 44 Hz body that rings for seconds, an octave and twelfth
// above it, two inharmonic membrane modes under the strike and a low thump.
// Upper partials die first, as they do on a real drum.
inline constexpr BoomVoicing kDeepBoom{
    44.0,
    {
        {1.0, 0.30f, 2.2},   // body
        {2.0, 0.14f, 0.9},   // octave
        {3.0, 0.045f, 0.45}, // twelfth, well clear of the 180 Hz binaural carrier
        {1.59, 0.07f, 0.18}, // membrane modes: the strike
        {2.14, 0.05f, 0.12},
    },
    0.45, 0.030, 0.14f, 0.010, 350.0, 0.0, 0.004,
};

// A phone speaker plays almost nothing below about 200 Hz: anything there
// only buzzes, at any volume. This voicing keeps the same 44 Hz pitch as
// the 5th to 8th harmonics alone (the ear fills in the missing
// fundamental), each well above the speaker's floor and the binaural tones.
inline constexpr BoomVoicing kSpeakerBoom{
    44.0,
    {
        {5.0, 0.070f, 0.9},   // 220 Hz
        {6.0, 0.055f, 0.7},   // 264 Hz
        {7.0, 0.040f, 0.5},   // 308 Hz
        {8.0, 0.030f, 0.35},  // 352 Hz
        {10.7, 0.012f, 0.10}, // a membrane mode: the strike
    },
    // A softer strike than the deep boom: a small speaker makes a fast
    // bright transient sound like a click.
    0.15, 0.025, 0.035f, 0.010, 700.0, 220.0, 0.015,
};

// A struck drum. Each strike rings in one ear, then the other.
//
// Each ear has its own voice. A strike re-excites that voice from wherever
// it is: phases run on and every level ramps from its current value over a
// few milliseconds, so a strike over a still-ringing tail never clicks. Two
// booms with different voicings stay in step, strike for strike.
class ResonantBoom {
public:
    static constexpr int kPartialCount = BoomVoicing::kPartialCount;

    explicit ResonantBoom(const BoomVoicing& voicing = kDeepBoom) noexcept : voicing_(voicing) {}

    void setSampleRate(double sampleRate) noexcept {
        const double rate = sampleRate > 0.0 ? sampleRate : 48000.0;
        sampleSeconds_ = 1.0 / rate;
        for (int k = 0; k < kPartialCount; ++k) {
            const auto& partial = voicing_.partials[k];
            step_[k] = partial.ratio * voicing_.frequencyHz / rate;
            decay_[k] = static_cast<float>(std::exp(-sampleSeconds_ / partial.decaySeconds));
        }
        dropDecay_ = static_cast<float>(std::exp(-sampleSeconds_ / voicing_.dropSeconds));
        thumpDecay_ = static_cast<float>(std::exp(-sampleSeconds_ / voicing_.thumpSeconds));
        thumpCoeff_ = onePole(voicing_.thumpHz, rate);
        floorCoeff_ = voicing_.thumpFloorHz > 0.0 ? onePole(voicing_.thumpFloorHz, rate) : 0.0f;
        attackSamples_ = std::max(1, static_cast<int>(voicing_.attackSeconds * rate));
    }

    // The first call strikes the left ear. Later strikes follow `advance`.
    void arm() noexcept {
        if (!struck_) strike();
    }

    float sample(int channel) const noexcept {
        const Voice& voice = voices_[channel & 1];
        if (!voice.sounding) return 0.0f;
        float y = (voice.thumpOut - voice.thumpFloor) * voice.thump * voicing_.thump * kThumpGain;
        for (int k = 0; k < kPartialCount; ++k) {
            y += static_cast<float>(std::sin(2.0 * std::numbers::pi * voice.phase[k])) * voice.level[k];
        }
        return y;
    }

    // Move one sample forward. `intervalSeconds` is the gap between strikes.
    void advance(double intervalSeconds) noexcept {
        for (auto& voice : voices_) {
            if (!voice.sounding) continue;
            const double pitch = 1.0 + voicing_.dropRatio * voice.drop;
            voice.drop *= dropDecay_;
            float loudest = 0.0f;
            for (int k = 0; k < kPartialCount; ++k) {
                if (voice.rising > 0) {
                    voice.level[k] += voice.rise[k];
                } else {
                    voice.level[k] *= decay_[k];
                }
                loudest = std::max(loudest, voice.level[k]);
                voice.phase[k] += step_[k] * pitch;
                voice.phase[k] -= std::floor(voice.phase[k]);
            }
            if (voice.rising > 0) {
                voice.thump += voice.thumpRise;
                --voice.rising;
            } else {
                voice.thump *= thumpDecay_;
            }
            voice.thumpLow += thumpCoeff_ * (noise_.bipolar() - voice.thumpLow);
            voice.thumpOut += thumpCoeff_ * (voice.thumpLow - voice.thumpOut);
            voice.thumpFloor += floorCoeff_ * (voice.thumpOut - voice.thumpFloor);
            voice.sounding = voice.rising > 0 || loudest > kSilent;
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
        struck_ = false;
    }

private:
    struct Voice {
        double phase[kPartialCount]{}; // in cycles, [0, 1)
        float level[kPartialCount]{};
        float rise[kPartialCount]{};   // per-sample step while rising
        int rising = 0;                // attack samples left
        double drop = 0.0;             // pitch drop, 1 at the strike
        float thump = 0.0f;            // thump envelope
        float thumpRise = 0.0f;
        float thumpLow = 0.0f;         // two-pole low-pass state
        float thumpOut = 0.0f;
        float thumpFloor = 0.0f;       // one-pole low-pass, subtracted: the high-pass
        bool sounding = false;
    };

    static float onePole(double hz, double rate) noexcept {
        return static_cast<float>(1.0 - std::exp(-2.0 * std::numbers::pi * hz / rate));
    }

    void strike() noexcept {
        ear_ ^= 1;
        Voice& voice = voices_[ear_];
        for (int k = 0; k < kPartialCount; ++k) {
            voice.rise[k] = (voicing_.partials[k].peak - voice.level[k]) / static_cast<float>(attackSamples_);
        }
        voice.thumpRise = (1.0f - voice.thump) / static_cast<float>(attackSamples_);
        voice.rising = attackSamples_;
        voice.drop = 1.0;
        voice.sounding = true;
        struck_ = true;
    }

    static constexpr float kSilent = 1.0e-5f;
    // Two one-pole low-pass stages leave white noise at roughly 0.1-0.2 RMS;
    // this brings the burst's peak near the voicing's thump.
    static constexpr float kThumpGain = 3.0f;

    BoomVoicing voicing_;
    double step_[kPartialCount]{};
    float decay_[kPartialCount]{};
    double sampleSeconds_ = 1.0 / 48000.0;
    float dropDecay_ = 0.0f;
    float thumpDecay_ = 0.0f;
    float thumpCoeff_ = 0.0f;
    float floorCoeff_ = 0.0f;
    int attackSamples_ = 192;
    double intervalPhase_ = 0.0;
    Voice voices_[2]{};
    Xoshiro256 noise_{0xB00Bu};
    int ear_ = 1; // strike() flips this, so the first hit is the left ear
    bool struck_ = false;
};

} // namespace humspan::dsp
