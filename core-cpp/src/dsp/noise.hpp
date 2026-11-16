// Colored noise generators. Header-only, allocation-free, real-time safe.
#pragma once

#include <cmath>
#include <cstdint>
#include <numbers>

namespace ambient::dsp {

// xoshiro256** (Blackman & Vigna), seeded through splitmix64.
class Xoshiro256 {
public:
    explicit Xoshiro256(uint64_t seed = 0) noexcept { reseed(seed); }

    void reseed(uint64_t seed) noexcept {
        for (auto& word : s_) {
            seed += 0x9E3779B97F4A7C15ull;
            uint64_t z = seed;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
            word = z ^ (z >> 31);
        }
    }

    uint64_t next() noexcept {
        const uint64_t result = rotl(s_[1] * 5, 7) * 9;
        const uint64_t t = s_[1] << 17;
        s_[2] ^= s_[0];
        s_[3] ^= s_[1];
        s_[1] ^= s_[2];
        s_[0] ^= s_[3];
        s_[2] ^= t;
        s_[3] = rotl(s_[3], 45);
        return result;
    }

    // Uniform in [-1, 1).
    float bipolar() noexcept {
        // Top 24 bits -> [0, 1) exactly representable in float.
        const float unit = static_cast<float>(next() >> 40) * (1.0f / 16777216.0f);
        return unit * 2.0f - 1.0f;
    }

private:
    static constexpr uint64_t rotl(uint64_t x, int k) noexcept { return (x << k) | (x >> (64 - k)); }
    uint64_t s_[4]{};
};

// Target RMS for every color, so switching colors keeps roughly the same
// loudness (about -15 dBFS RMS before volume, leaving headroom for the peaks
// of pink and brown noise, which reach 4-5x RMS).
inline constexpr float kNoiseRms = 0.18f;

// Uniform white noise has RMS 1/sqrt(3).
inline constexpr float kWhiteGain = kNoiseRms * 1.7320508f;

// Paul Kellet's refined pink filter (accurate to +/-0.05 dB above ~9 Hz at
// 44.1 kHz; close enough at 48 kHz). Gain measured to land on kNoiseRms.
class PinkFilter {
public:
    float process(float white) noexcept {
        b0_ = 0.99886f * b0_ + white * 0.0555179f;
        b1_ = 0.99332f * b1_ + white * 0.0750759f;
        b2_ = 0.96900f * b2_ + white * 0.1538520f;
        b3_ = 0.86650f * b3_ + white * 0.3104856f;
        b4_ = 0.55000f * b4_ + white * 0.5329522f;
        b5_ = -0.7616f * b5_ - white * 0.0168980f;
        const float pink = b0_ + b1_ + b2_ + b3_ + b4_ + b5_ + b6_ + white * 0.5362f;
        b6_ = white * 0.115926f;
        return pink * kGain;
    }

    void reset() noexcept { b0_ = b1_ = b2_ = b3_ = b4_ = b5_ = b6_ = 0.0f; }

    // Uniform white input (RMS 0.577) gives pink RMS of about 1.764 (measured).
    static constexpr float kGain = kNoiseRms / 1.764f;

private:
    float b0_ = 0, b1_ = 0, b2_ = 0, b3_ = 0, b4_ = 0, b5_ = 0, b6_ = 0;
};

// Brown (red) noise: leaky integrator y[n] = a*y[n-1] + (1-a)*x[n].
// -6 dB/octave above the corner frequency, flat below it (so no DC drift).
// Normalised analytically: var(y) = var(x) * (1-a)/(1+a).
class BrownFilter {
public:
    explicit BrownFilter(double sampleRate = 48000.0, double cornerHz = 8.0) noexcept {
        setSampleRate(sampleRate, cornerHz);
    }

    void setSampleRate(double sampleRate, double cornerHz = 8.0) noexcept {
        const double a = std::exp(-2.0 * std::numbers::pi * cornerHz / sampleRate);
        a_ = static_cast<float>(a);
        oneMinusA_ = static_cast<float>(1.0 - a);
        const double rmsIn = 1.0 / std::sqrt(3.0);
        gain_ = static_cast<float>(kNoiseRms / (rmsIn * std::sqrt((1.0 - a) / (1.0 + a))));
    }

    float process(float white) noexcept {
        y_ = a_ * y_ + oneMinusA_ * white;
        return y_ * gain_;
    }

    void reset() noexcept { y_ = 0.0f; }

private:
    float a_ = 0, oneMinusA_ = 0, gain_ = 0, y_ = 0;
};

} // namespace ambient::dsp
