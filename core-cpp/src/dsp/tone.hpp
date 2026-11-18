// Tone generators. Header-only, allocation-free, real-time safe.
#pragma once

#include "dsp/noise.hpp"

#include <cmath>
#include <numbers>

namespace ambient::dsp {

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

} // namespace ambient::dsp
