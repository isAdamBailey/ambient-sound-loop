// libhumspansynth unit tests. Plain executable, no framework: each test
// returns normally or records a failure; main() exits non-zero on failure.
#include "humspan_engine.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <complex>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <numbers>
#include <vector>

// ---------------------------------------------------------------------------
// Allocation tracking: counts global operator new calls while armed.
// ---------------------------------------------------------------------------
static std::atomic<bool> g_trackAllocations{false};
static std::atomic<int> g_allocations{0};

void* operator new(std::size_t size) {
    if (g_trackAllocations.load(std::memory_order_relaxed)) {
        g_allocations.fetch_add(1, std::memory_order_relaxed);
    }
    if (void* p = std::malloc(size == 0 ? 1 : size)) {
        return p;
    }
    throw std::bad_alloc();
}
void* operator new[](std::size_t size) { return operator new(size); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

// ---------------------------------------------------------------------------
static int g_failures = 0;

// White and pink at full volume: 8 dB under the old 0.18 reference.
constexpr double kBedRms = 0.07165929;

#define CHECK(cond, ...)                                                              \
    do {                                                                              \
        if (!(cond)) {                                                                \
            ++g_failures;                                                             \
            std::printf("  FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond);             \
            std::printf(__VA_ARGS__);                                                 \
            std::printf("\n");                                                        \
        }                                                                             \
    } while (0)

constexpr uint32_t kRate = 48000;
constexpr int kBlock = 512;

struct Engine {
    explicit Engine(uint32_t rate = kRate, uint64_t seed = 1) : e(humspan_engine_create(rate, seed)) {}
    ~Engine() { humspan_engine_destroy(e); }
    humspan_engine* e;
};

// Renders `frames` frames, returns interleaved stereo.
static std::vector<float> render(humspan_engine* e, int64_t frames, int* lastResult = nullptr) {
    std::vector<float> out(static_cast<size_t>(frames) * 2);
    int64_t done = 0;
    int result = 0;
    while (done < frames) {
        const int n = static_cast<int>(std::min<int64_t>(kBlock, frames - done));
        result = humspan_engine_render(e, out.data() + done * 2, n);
        done += n;
    }
    if (lastResult) *lastResult = result;
    return out;
}

static double rms(const std::vector<float>& x, size_t fromFrame, size_t toFrame) {
    double sum = 0;
    for (size_t i = fromFrame * 2; i < toFrame * 2; ++i) sum += double(x[i]) * x[i];
    return std::sqrt(sum / double((toFrame - fromFrame) * 2));
}

static double toDb(double ratio) { return 20.0 * std::log10(ratio); }

// Index (in frames) one past the last non-zero frame.
static int64_t soundingFrames(const std::vector<float>& x) {
    for (int64_t i = int64_t(x.size()) - 1; i >= 0; --i) {
        if (x[size_t(i)] != 0.0f) return i / 2 + 1;
    }
    return 0;
}

// Render until the session finishes; returns total frames rendered.
static int64_t renderUntilFinished(humspan_engine* e, int64_t limit, std::vector<float>* tail = nullptr) {
    std::vector<float> block(kBlock * 2);
    int64_t frames = 0;
    while (frames < limit) {
        const int r = humspan_engine_render(e, block.data(), kBlock);
        if (r == 0) {
            // Count only the frames that sounded in this final block.
            int64_t sounding = soundingFrames(block);
            if (tail) *tail = block;
            return frames + sounding;
        }
        frames += kBlock;
    }
    return -1;
}

// --- spectrum ---------------------------------------------------------------
static void fft(std::vector<std::complex<double>>& a) {
    const size_t n = a.size();
    for (size_t i = 1, j = 0; i < n; ++i) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        const double ang = -2.0 * std::numbers::pi / double(len);
        const std::complex<double> wl(std::cos(ang), std::sin(ang));
        for (size_t i = 0; i < n; i += len) {
            std::complex<double> w(1);
            for (size_t k = 0; k < len / 2; ++k) {
                auto u = a[i + k], v = a[i + k + len / 2] * w;
                a[i + k] = u + v;
                a[i + k + len / 2] = u - v;
                w *= wl;
            }
        }
    }
}

// Mean power spectral density (left channel) over [lo, hi) Hz.
static double bandDensity(const std::vector<double>& psd, double lo, double hi, size_t n) {
    const double binHz = double(kRate) / double(n);
    double sum = 0;
    int count = 0;
    for (size_t k = size_t(lo / binHz); k < size_t(hi / binHz); ++k, ++count) sum += psd[k];
    return sum / count;
}

static std::vector<double> averagedPsd(const std::vector<float>& x, size_t n) {
    std::vector<double> psd(n / 2, 0.0);
    const size_t frames = x.size() / 2;
    int blocks = 0;
    for (size_t start = 0; start + n <= frames; start += n, ++blocks) {
        std::vector<std::complex<double>> a(n);
        for (size_t i = 0; i < n; ++i) {
            const double w = 0.5 - 0.5 * std::cos(2.0 * std::numbers::pi * double(i) / double(n));
            a[i] = x[(start + i) * 2] * w;
        }
        fft(a);
        for (size_t k = 0; k < n / 2; ++k) psd[k] += std::norm(a[k]);
    }
    for (auto& p : psd) p /= blocks;
    return psd;
}

// ---------------------------------------------------------------------------
static void testSpectralSlopeAndLevel() {
    std::printf("spectral slope and level\n");
    struct Case { humspan_noise_color color; const char* name; double slopeDbPerOctave; };
    const Case cases[] = {
        {HUMSPAN_NOISE_WHITE, "white", 0.0},
        {HUMSPAN_NOISE_PINK, "pink", -3.0},
        {HUMSPAN_NOISE_BROWN, "brown", -6.0},
    };
    for (const auto& c : cases) {
        Engine eng;
        humspan_engine_set_noise_color(eng.e, c.color);
        humspan_engine_set_volume(eng.e, 1.0f);
        humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
        render(eng.e, kRate / 2); // let the colour/volume smoothing settle
        const auto x = render(eng.e, kRate * 20);

        const size_t n = 4096;
        const auto psd = averagedPsd(x, n);
        // 500-1000 Hz vs 4-8 kHz: three octaves apart.
        const double slope = 10.0 * std::log10(bandDensity(psd, 4000, 8000, n) / bandDensity(psd, 500, 1000, n)) / 3.0;
        CHECK(std::fabs(slope - c.slopeDbPerOctave) < 0.5, "%s slope %.2f dB/oct, want %.1f", c.name, slope,
              c.slopeDbPerOctave);

        // White and pink are 8 dB under the old 0.18 reference. Brown is 9 dB
        // above them (about +1 dB versus 0.18) so it matches by ear and stays clean.
        const double targetDb = c.color == HUMSPAN_NOISE_BROWN ? 1.0 : -8.0;
        const double level = toDb(rms(x, 0, x.size() / 2) / 0.18);
        CHECK(std::fabs(level - targetDb) < 1.0, "%s level %.2f dB, want %.1f", c.name, level, targetDb);
    }
}

static void testDeterminism() {
    std::printf("determinism\n");
    Engine a(kRate, 42), b(kRate, 42), c(kRate, 43);
    for (auto* e : {a.e, b.e, c.e}) humspan_engine_start(e, 0.0, 0.0, 0.0);
    const auto xa = render(a.e, 10000), xb = render(b.e, 10000), xc = render(c.e, 10000);
    CHECK(xa == xb, "same seed should give identical output");
    CHECK(xa != xc, "different seeds should differ");

    // Left and right are independent streams (decorrelated, wide image).
    double lr = 0, ll = 0, rr = 0;
    for (size_t i = 0; i < xa.size(); i += 2) {
        lr += double(xa[i]) * xa[i + 1];
        ll += double(xa[i]) * xa[i];
        rr += double(xa[i + 1]) * xa[i + 1];
    }
    const double corr = lr / std::sqrt(ll * rr);
    CHECK(std::fabs(corr) < 0.1, "L/R correlation %.3f", corr);
}

static void testTimerIsFrameAccurate() {
    std::printf("timer is frame-accurate\n");
    Engine eng;
    humspan_engine_start(eng.e, 2.5, 0.0, 0.0);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 10);
    CHECK(frames == 120000, "2.5 s at 48 kHz rendered %lld frames, want 120000", (long long)frames);
    CHECK(!humspan_engine_is_playing(eng.e), "should report finished");
}

static void testTimerSurvivesSampleRateChange() {
    std::printf("timer survives a sample-rate change\n");
    Engine eng;
    humspan_engine_start(eng.e, 2.5, 0.0, 0.0);
    render(eng.e, 48000); // exactly 1.0 s at 48 kHz
    CHECK(std::fabs(humspan_engine_elapsed_seconds(eng.e) - 1.0) < 1e-9, "elapsed %.6f",
          humspan_engine_elapsed_seconds(eng.e));

    // Route change: the OS reopens the stream at 44.1 kHz.
    humspan_engine_set_sample_rate(eng.e, 44100);
    const int64_t frames = renderUntilFinished(eng.e, 44100 * 10);
    CHECK(frames == 66150, "remaining 1.5 s at 44.1 kHz rendered %lld frames, want 66150", (long long)frames);
}

static void testRemainingSeconds() {
    std::printf("remaining seconds\n");
    Engine eng;
    CHECK(humspan_engine_remaining_seconds(eng.e) == 0.0, "idle engine has nothing remaining");

    humspan_engine_start(eng.e, 10.0, 0.0, 0.0);
    render(eng.e, kRate * 4);
    CHECK(std::fabs(humspan_engine_remaining_seconds(eng.e) - 6.0) < 1e-9, "remaining %.6f, want 6",
          humspan_engine_remaining_seconds(eng.e));
    renderUntilFinished(eng.e, kRate * 10);
    CHECK(humspan_engine_remaining_seconds(eng.e) == 0.0, "finished session has nothing remaining");

    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    CHECK(humspan_engine_remaining_seconds(eng.e) < 0.0, "until-stopped session reports negative");
}

static void testPauseHoldsPlaceAndResumes() {
    std::printf("pause holds the session's place and resumes\n");
    Engine eng;
    humspan_engine_start(eng.e, 10.0, 0.0, 0.0);
    render(eng.e, kRate * 2);
    CHECK(!humspan_engine_is_paused(eng.e), "not paused before pause");

    humspan_engine_pause(eng.e, 0.1); // headphones out
    const auto fade = render(eng.e, kRate / 2);
    CHECK(rms(fade, 0, kRate / 50) > 0.0, "pause fades rather than cutting");
    CHECK(soundingFrames(fade) <= int64_t(0.1 * kRate), "silent after the 0.1 s pause fade");
    CHECK(humspan_engine_is_paused(eng.e) && humspan_engine_is_playing(eng.e), "paused session is still active");

    const auto held = render(eng.e, kRate * 3);
    CHECK(soundingFrames(held) == 0, "no output while paused");
    CHECK(std::fabs(humspan_engine_elapsed_seconds(eng.e) - 2.1) < 1e-4, "elapsed frozen at %.4f, want 2.1",
          humspan_engine_elapsed_seconds(eng.e));
    CHECK(std::fabs(humspan_engine_remaining_seconds(eng.e) - 7.9) < 1e-4, "remaining %.4f, want 7.9",
          humspan_engine_remaining_seconds(eng.e));

    humspan_engine_resume(eng.e, 0.5);
    const auto rise = render(eng.e, kRate);
    CHECK(!humspan_engine_is_paused(eng.e), "resumed");
    auto window = [&](double t) { return rms(rise, size_t(t * kRate), size_t((t + 0.05) * kRate)); };
    CHECK(window(0.0) < 0.1 * window(0.8), "resume fades in from silence");
    CHECK(window(0.1) < window(0.25) && window(0.25) < window(0.4), "level rises over the resume fade");

    // 7.9 s remained at the pause; 1 s of it has now played.
    const int64_t frames = renderUntilFinished(eng.e, kRate * 20);
    CHECK(std::llabs(frames - int64_t(6.9 * kRate)) <= 2, "rest of session %lld frames, want %lld",
          (long long)frames, (long long)(6.9 * kRate));
}

static void testStopWhilePausedEndsAtOnce() {
    std::printf("stop while paused ends at once\n");
    Engine eng;
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    humspan_engine_pause(eng.e, 0.05);
    render(eng.e, kRate);
    humspan_engine_stop(eng.e, 1.0);
    int result = 1;
    render(eng.e, kBlock, &result);
    CHECK(result == 0 && !humspan_engine_is_playing(eng.e) && !humspan_engine_is_paused(eng.e),
          "stop from pause should finish in the next block");
}

static void testStopDuringPauseFadeFinishes() {
    std::printf("stop during a pause fade still finishes\n");
    Engine eng;
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    humspan_engine_pause(eng.e, 0.2);
    render(eng.e, kRate / 10); // halfway through the pause fade
    humspan_engine_stop(eng.e, 1.0);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 5);
    CHECK(frames >= 0 && frames <= int64_t(1.0 * kRate) + kBlock, "session should end, took %lld frames",
          (long long)frames);
    CHECK(!humspan_engine_is_playing(eng.e) && !humspan_engine_is_paused(eng.e), "finished, not paused");
}

static void testDuckLowersLevelAndKeepsClock() {
    std::printf("duck lowers the level within 500 ms and keeps the clock\n");
    Engine eng;
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);

    humspan_engine_set_duck_gain(eng.e, 0.25f); // phone call: -12 dB
    const auto ducking = render(eng.e, kRate);
    auto window = [&](const std::vector<float>& x, double t) {
        return rms(x, size_t(t * kRate), size_t((t + 0.1) * kRate));
    };
    const double early = toDb(window(ducking, 0.0) / kBedRms);
    const double settled = toDb(window(ducking, 0.5) / kBedRms);
    CHECK(early > -9.0, "duck ramps rather than cutting (%.1f dB in first 100 ms)", early);
    CHECK(std::fabs(settled + 12.0) < 1.0, "ducked level %.1f dB, want -12 within 500 ms", settled);
    CHECK(std::fabs(humspan_engine_elapsed_seconds(eng.e) - 2.0) < 1e-9, "clock kept running: %.4f",
          humspan_engine_elapsed_seconds(eng.e));

    humspan_engine_set_duck_gain(eng.e, 1.0f);
    const auto restored = render(eng.e, kRate);
    CHECK(std::fabs(toDb(window(restored, 0.5) / kBedRms)) < 1.0, "level back to full after the duck");
}

// Amplitude of the sinusoid at `hz` in one channel (0 = left), by projection
// over [from, to) frames. Exact for tones with whole cycles in the window.
static double toneAmplitude(const std::vector<float>& x, int channel, double hz, size_t from, size_t to) {
    std::complex<double> sum = 0;
    for (size_t i = from; i < to; ++i) {
        const double ph = 2.0 * std::numbers::pi * hz * double(i - from) / double(kRate);
        sum += double(x[i * 2 + size_t(channel)]) * std::complex<double>(std::cos(ph), -std::sin(ph));
    }
    return 2.0 * std::abs(sum) / double(to - from);
}

static void testBinauralBeatToneAndLevel() {
    std::printf("binaural beat: 180 Hz left, 180 + beat right, -6 dB under the noise\n");
    // A sine with RMS kBedRms, 6 dB down: amplitude kBedRms * 0.5 * sqrt(2).
    const double want = kBedRms * 0.5 * std::numbers::sqrt2;
    Engine eng;
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate / 2);
    // Tones are measured over 8 s so pink noise's own projection onto them
    // (about 0.002, -36 dB re the tone) stays out of the way.
    const auto off = render(eng.e, kRate * 8);
    CHECK(toneAmplitude(off, 0, 180, 0, 8 * kRate) < 0.05 * want, "no tone while off");

    humspan_engine_set_binaural(eng.e, 1);
    humspan_engine_set_beat_frequency(eng.e, 4.0f);
    render(eng.e, kRate / 2); // let the layer fade in
    auto x = render(eng.e, kRate * 8);
    const double left = toneAmplitude(x, 0, 180, 0, 8 * kRate);
    const double right = toneAmplitude(x, 1, 184, 0, 8 * kRate);
    CHECK(std::fabs(toDb(left / want)) < 0.5, "left 180 Hz is %.2f dB from target", toDb(left / want));
    CHECK(std::fabs(toDb(right / want)) < 0.5, "right 184 Hz is %.2f dB from target", toDb(right / want));
    CHECK(toneAmplitude(x, 0, 184, 0, 8 * kRate) < 0.05 * want, "left has no 184 Hz");
    CHECK(toneAmplitude(x, 1, 180, 0, 8 * kRate) < 0.05 * want, "right has no 180 Hz");

    humspan_engine_set_beat_frequency(eng.e, 10.0f);
    render(eng.e, kRate / 2);
    x = render(eng.e, kRate * 8);
    CHECK(std::fabs(toDb(toneAmplitude(x, 1, 190, 0, 8 * kRate) / want)) < 0.5, "10 Hz beat puts right at 190 Hz");
    CHECK(std::fabs(toDb(toneAmplitude(x, 0, 180, 0, 8 * kRate) / want)) < 0.5, "carrier stays at 180 Hz");

    humspan_engine_set_volume(eng.e, 0.5f); // the beat follows the session volume
    render(eng.e, kRate / 2);
    x = render(eng.e, kRate * 8);
    CHECK(std::fabs(toDb(toneAmplitude(x, 0, 180, 0, 8 * kRate) / (0.5 * want))) < 0.5, "beat follows volume");

    humspan_engine_set_binaural(eng.e, 0);
    const auto fading = render(eng.e, kRate / 2);
    CHECK(toneAmplitude(fading, 0, 180, 0, kRate / 100) > 0.1 * 0.5 * want, "switching off fades, not cuts");
    x = render(eng.e, kRate * 8);
    CHECK(toneAmplitude(x, 0, 180, 0, 8 * kRate) < 0.05 * want, "no tone after switching off");
}

static void testBoomAlternatesEars() {
    std::printf("boom strikes left then right, under the noise, with the beat\n");
    Engine quiet(kRate, 9), struck(kRate, 9);
    humspan_engine_set_volume(quiet.e, 1.0f);
    humspan_engine_set_volume(struck.e, 1.0f);
    humspan_engine_set_boom(struck.e, 1);
    humspan_engine_set_boom_interval(struck.e, 4.0f);
    humspan_engine_set_binaural(quiet.e, 1);
    humspan_engine_set_binaural(struck.e, 1);
    humspan_engine_set_beat_frequency(quiet.e, 4.0f);
    humspan_engine_set_beat_frequency(struck.e, 4.0f);
    for (auto* e : {quiet.e, struck.e}) humspan_engine_start(e, 0.0, 0.0, 0.0);

    const auto a = render(quiet.e, kRate * 8);
    const auto b = render(struck.e, kRate * 8);
    std::vector<float> diff(a.size());
    float peak = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        diff[i] = b[i] - a[i];
        peak = std::max(peak, std::fabs(b[i]));
    }
    CHECK(peak < 1.0f, "boom plus noise plus beat peaks at %.3f", peak);

    auto side = [&](int channel, size_t from, size_t to) {
        double sum = 0;
        for (size_t i = from; i < to; ++i) {
            const float s = diff[i * 2 + size_t(channel)];
            sum += double(s) * s;
        }
        return std::sqrt(sum / double(to - from));
    };
    const size_t attack = size_t(0.12 * kRate);
    CHECK(side(0, size_t(0.02 * kRate), attack) > 5.0 * side(1, size_t(0.02 * kRate), attack),
          "the first strike is in the left ear");
    const size_t second = 4 * kRate;
    CHECK(side(1, second, second + attack) > 5.0 * side(0, second, second + attack),
          "the next strike is in the right ear");

    const size_t toneEnd = size_t(0.4 * kRate);
    const double low = toneAmplitude(diff, 0, 44, size_t(0.05 * kRate), toneEnd);
    const double octave = toneAmplitude(diff, 0, 88, size_t(0.05 * kRate), toneEnd);
    CHECK(low > 0.10, "the strike rings at 44 Hz (amplitude %.3f)", low);
    CHECK(octave > 0.05, "the octave is loud enough to hear (amplitude %.3f)", octave);

    // A struck attack: most of the strike's peak arrives in the first 15 ms.
    float early = 0, strikePeak = 0;
    for (size_t i = 0; i < size_t(0.5 * kRate); ++i) {
        const float s = std::fabs(diff[i * 2]);
        strikePeak = std::max(strikePeak, s);
        if (i < size_t(0.015 * kRate)) early = std::max(early, s);
    }
    CHECK(early > 0.6f * strikePeak, "the strike lands within 15 ms (%.3f of %.3f)", early, strikePeak);
    // Headroom: a strike leaves room for white or pink noise under the
    // clipper's knee.
    CHECK(strikePeak < 0.5f, "the strike peaks at %.3f", strikePeak);

    const double want = kBedRms * 0.5 * std::numbers::sqrt2;
    const double leftBeat = toneAmplitude(b, 0, 180, kRate, 2 * kRate);
    CHECK(std::fabs(toDb(leftBeat / want)) < 1.0, "binaural stays with the boom, %.2f dB", toDb(leftBeat / want));

    humspan_engine_set_boom(struck.e, 0);
    const auto gone = render(struck.e, kRate);
    const auto still = render(quiet.e, kRate);
    double leftover = 0;
    for (size_t i = gone.size() / 2; i < gone.size(); ++i) {
        const double d = double(gone[i]) - still[i];
        leftover += d * d;
    }
    leftover = std::sqrt(leftover / double(gone.size() / 2));
    CHECK(leftover < 0.01, "switching the boom off fades it out (residual %.4f)", leftover);
}

static void testBoomRetriggerIsSmooth() {
    std::printf("a strike over a ringing tail does not click\n");
    // At the shortest gap each ear is struck again while still ringing. A
    // click shows as a sample-to-sample jump far above the tone's slope.
    Engine eng(kRate, 3);
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_set_noise(eng.e, 0);
    humspan_engine_set_boom(eng.e, 1);
    humspan_engine_set_boom_interval(eng.e, 1.0f);
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    const auto x = render(eng.e, kRate * 6);
    float jump = 0;
    for (size_t i = 2; i < x.size(); ++i) jump = std::max(jump, std::fabs(x[i] - x[i - 2]));
    CHECK(jump < 0.01f, "largest sample step %.4f", jump);
}

static void testSpeakerBoomStaysAboveTheSpeakerFloor() {
    std::printf("on a phone speaker the boom keeps its pitch from 220 Hz up\n");
    auto boomOnly = [](bool speaker) {
        Engine eng(kRate, 5);
        humspan_engine_set_volume(eng.e, 1.0f);
        humspan_engine_set_noise(eng.e, 0);
        humspan_engine_set_boom(eng.e, 1);
        humspan_engine_set_boom_interval(eng.e, 4.0f);
        humspan_engine_set_speaker_output(eng.e, speaker ? 1 : 0);
        humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
        return render(eng.e, kRate * 4);
    };
    const auto deep = boomOnly(false);
    const auto small = boomOnly(true);
    const size_t from = size_t(0.05 * kRate), to = size_t(0.5 * kRate);
    const double strike = rms(small, from, to);
    CHECK(strike > 0.02, "the speaker boom sounds (rms %.4f)", strike);
    for (double hz : {44.0, 88.0, 132.0}) {
        const double a = toneAmplitude(small, 0, hz, from, to);
        CHECK(a < 0.01, "speaker boom keeps %.0f Hz out (amplitude %.4f)", hz, a);
    }
    CHECK(toneAmplitude(small, 0, 220, from, to) > 0.03, "speaker boom rings at 220 Hz");
    CHECK(toneAmplitude(deep, 0, 220, from, to) < 0.01, "the deep boom is unchanged");

    // A route change mid-strike crossfades: no step larger than the tone's own.
    Engine eng(kRate, 5);
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_set_noise(eng.e, 0);
    humspan_engine_set_boom(eng.e, 1);
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    auto x = render(eng.e, kRate / 10);
    humspan_engine_set_speaker_output(eng.e, 1);
    const auto y = render(eng.e, kRate / 2);
    x.insert(x.end(), y.begin(), y.end());
    float jump = 0;
    for (size_t i = size_t(0.05 * kRate) * 2; i < x.size(); ++i) jump = std::max(jump, std::fabs(x[i] - x[i - 2]));
    CHECK(jump < 0.03f, "switching to the speaker voicing steps at most %.4f", jump);
}

// A started, settled engine at full volume with the given layers.
static void startLayers(humspan_engine* e, bool noise, bool binaural, bool boom) {
    humspan_engine_set_volume(e, 1.0f);
    humspan_engine_set_noise(e, noise ? 1 : 0);
    humspan_engine_set_binaural(e, binaural ? 1 : 0);
    humspan_engine_set_beat_frequency(e, 4.0f);
    humspan_engine_set_boom(e, boom ? 1 : 0);
    humspan_engine_set_boom_interval(e, 4.0f);
    humspan_engine_start(e, 0.0, 0.0, 0.0);
}

static std::vector<float> minus(const std::vector<float>& a, const std::vector<float>& b) {
    std::vector<float> d(a.size());
    for (size_t i = 0; i < a.size(); ++i) d[i] = a[i] - b[i];
    return d;
}

static void testEachLayerAlone() {
    std::printf("each layer plays alone at its usual level; all off is silent and timed\n");
    const double want = kBedRms * 0.5 * std::numbers::sqrt2; // binaural amplitude

    { // noise only: the default, unchanged
        Engine eng;
        startLayers(eng.e, true, false, false);
        render(eng.e, kRate / 2);
        const auto x = render(eng.e, kRate * 10);
        CHECK(std::fabs(toDb(rms(x, 0, x.size() / 2) / kBedRms)) < 0.5, "noise alone %.2f dB from the bed",
              toDb(rms(x, 0, x.size() / 2) / kBedRms));
    }
    { // binaural only: a pure tone pair at the usual level
        Engine eng;
        startLayers(eng.e, false, true, false);
        render(eng.e, kRate / 2);
        const auto x = render(eng.e, kRate * 8);
        const double left = toneAmplitude(x, 0, 180, 0, 8 * kRate);
        const double right = toneAmplitude(x, 1, 184, 0, 8 * kRate);
        CHECK(std::fabs(toDb(left / want)) < 0.2, "binaural alone, left %.2f dB from target", toDb(left / want));
        CHECK(std::fabs(toDb(right / want)) < 0.2, "binaural alone, right %.2f dB from target", toDb(right / want));
        // Nothing but the tone: its RMS is amplitude / sqrt 2.
        CHECK(std::fabs(toDb(rms(x, 0, x.size() / 2) / (want / std::numbers::sqrt2))) < 0.2,
              "binaural alone carries no noise");
    }
    { // boom only: the same strikes as the boom over the noise
        Engine alone(kRate, 9), withNoise(kRate, 9), noiseOnly(kRate, 9);
        startLayers(alone.e, false, false, true);
        startLayers(withNoise.e, true, false, true);
        startLayers(noiseOnly.e, true, false, false);
        const auto a = render(alone.e, kRate * 8);
        const auto boom = minus(render(withNoise.e, kRate * 8), render(noiseOnly.e, kRate * 8));
        const double ra = rms(a, 0, a.size() / 2), rb = rms(boom, 0, boom.size() / 2);
        CHECK(ra > 0.01, "boom alone sounds (rms %.4f)", ra);
        CHECK(std::fabs(toDb(ra / rb)) < 0.2, "boom alone %.2f dB from the boom over noise", toDb(ra / rb));
    }
    { // all off: silence, while the session and its clock carry on
        Engine eng;
        startLayers(eng.e, false, false, false);
        int result = 0;
        const auto x = render(eng.e, kRate * 3, &result);
        CHECK(soundingFrames(x) == 0, "all layers off renders silence");
        CHECK(result == 1 && humspan_engine_is_playing(eng.e), "the silent session is still active");
        CHECK(std::fabs(humspan_engine_elapsed_seconds(eng.e) - 3.0) < 1e-9, "clock ran to %.4f, want 3",
              humspan_engine_elapsed_seconds(eng.e));

        humspan_engine_set_noise(eng.e, 1); // a layer comes back on mid-session
        render(eng.e, kRate / 2);
        const auto back = render(eng.e, kRate * 5);
        CHECK(std::fabs(toDb(rms(back, 0, back.size() / 2) / kBedRms)) < 0.5, "noise back at the bed level");
    }
}

static void testNoiseToggleKeepsColorAndFades() {
    std::printf("noise on/off fades, keeps the color, and leaves the beat alone\n");
    const double want = kBedRms * 0.5 * std::numbers::sqrt2;
    Engine eng;
    startLayers(eng.e, true, true, false);
    render(eng.e, kRate / 2);
    const auto before = render(eng.e, kRate / 10);

    humspan_engine_set_noise(eng.e, 0);
    const auto fading = render(eng.e, kRate);
    const double justAfter = rms(fading, 0, kRate / 200); // first 5 ms
    CHECK(justAfter > 0.5 * rms(before, 0, before.size() / 2), "noise off fades rather than cutting");
    const auto off = render(eng.e, kRate * 8);
    CHECK(std::fabs(toDb(rms(off, 0, off.size() / 2) / (want / std::numbers::sqrt2))) < 0.2,
          "only the beat is left once noise is off");
    CHECK(std::fabs(toDb(toneAmplitude(off, 0, 180, 0, 8 * kRate) / want)) < 0.2, "the beat keeps its level");

    // A color chosen while noise is off is the one that comes back.
    humspan_engine_set_binaural(eng.e, 0);
    humspan_engine_set_noise_color(eng.e, HUMSPAN_NOISE_BROWN);
    render(eng.e, kRate);
    humspan_engine_set_noise(eng.e, 1);
    render(eng.e, kRate / 2);
    const auto x = render(eng.e, kRate * 20);
    const size_t n = 4096;
    const auto psd = averagedPsd(x, n);
    const double slope = 10.0 * std::log10(bandDensity(psd, 4000, 8000, n) / bandDensity(psd, 500, 1000, n)) / 3.0;
    CHECK(std::fabs(slope + 6.0) < 0.5, "noise came back brown, slope %.2f dB/oct", slope);
    CHECK(std::fabs(toDb(rms(x, 0, x.size() / 2) / 0.18) - 1.0) < 1.0, "brown back at its level");
}

static void testLayerLevels() {
    std::printf("a layer level of 0.5 drops only that layer by 6 dB\n");
    const double want = kBedRms * 0.5 * std::numbers::sqrt2;
    const int64_t len = kRate * 8;
    // Same seed throughout, so the layers separate by subtraction.
    auto mix = [&](bool noise, bool binaural, bool boom, float noiseLevel, float binauralLevel, float boomLevel) {
        Engine eng(kRate, 5);
        humspan_engine_set_noise_level(eng.e, noiseLevel);
        humspan_engine_set_binaural_level(eng.e, binauralLevel);
        humspan_engine_set_boom_level(eng.e, boomLevel);
        startLayers(eng.e, noise, binaural, boom);
        return render(eng.e, len);
    };
    const auto noiseFull = mix(true, false, false, 1, 1, 1);
    const auto noiseHalf = mix(true, false, false, 0.5f, 1, 1);
    const auto toneFull = mix(false, true, false, 1, 1, 1);
    const auto toneHalf = mix(false, true, false, 1, 0.5f, 1);
    const auto boomFull = mix(false, false, true, 1, 1, 1);
    const auto boomHalf = mix(false, false, true, 1, 1, 0.5f);
    auto level = [](const std::vector<float>& x) { return rms(x, 0, x.size() / 2); };

    CHECK(std::fabs(toDb(level(noiseHalf) / level(noiseFull)) + 6.02) < 0.2, "noise at 0.5 is %.2f dB",
          toDb(level(noiseHalf) / level(noiseFull)));
    CHECK(std::fabs(toDb(toneAmplitude(toneHalf, 0, 180, 0, len) / want) + 6.02) < 0.2, "binaural at 0.5 is %.2f dB",
          toDb(toneAmplitude(toneHalf, 0, 180, 0, len) / want));
    CHECK(std::fabs(toDb(level(boomHalf) / level(boomFull)) + 6.02) < 0.2, "boom at 0.5 is %.2f dB",
          toDb(level(boomHalf) / level(boomFull)));

    // Lowering one layer in the full mix leaves the other two as they were.
    const auto all = mix(true, true, true, 1, 1, 1);
    const auto lowNoise = mix(true, true, true, 0.5f, 1, 1);
    const auto lowTone = mix(true, true, true, 1, 0.5f, 1);
    const auto lowBoom = mix(true, true, true, 1, 1, 0.5f);
    const auto others = minus(all, noiseFull); // binaural + boom
    CHECK(level(minus(minus(lowNoise, noiseHalf), others)) < 1e-3, "noise level leaves the beat and boom");
    CHECK(level(minus(minus(lowTone, toneHalf), minus(all, toneFull))) < 1e-3,
          "binaural level leaves the noise and boom");
    CHECK(level(minus(minus(lowBoom, boomHalf), minus(all, boomFull))) < 1e-3,
          "boom level leaves the noise and beat");

    // Clamped to [0, 1]: a level never raises a layer, and 0 silences it.
    const auto over = mix(false, true, false, 1, 4.0f, 1);
    CHECK(std::fabs(toDb(toneAmplitude(over, 0, 180, 0, len) / want)) < 0.2, "a level above 1 clamps to 1");
    CHECK(soundingFrames(mix(true, true, true, 0, 0, 0)) == 0, "all levels at 0 are silent");
}

static void testLevelChangesDoNotClick() {
    std::printf("moving a level mid-render does not click\n");
    // A pure 184 Hz tone of amplitude A moves at most A * 2 pi f / rate per
    // sample; an unsmoothed gain step would jump far beyond that.
    const double want = kBedRms * 0.5 * std::numbers::sqrt2;
    const double maxStep = want * 2.0 * std::numbers::pi * 184.0 / kRate;
    Engine eng;
    startLayers(eng.e, false, true, false);
    render(eng.e, kRate / 2);
    float largest = 0;
    float prev[2] = {0, 0};
    bool first = true;
    for (float target : {0.1f, 1.0f, 0.0f, 0.8f}) {
        humspan_engine_set_binaural_level(eng.e, target);
        humspan_engine_set_noise(eng.e, 0); // a no-op toggle while the tone moves
        const auto x = render(eng.e, kRate / 4);
        for (size_t i = 0; i < x.size(); i += 2) {
            for (int ch = 0; ch < 2; ++ch) {
                if (!first) largest = std::max(largest, std::fabs(x[i + size_t(ch)] - prev[ch]));
                prev[ch] = x[i + size_t(ch)];
            }
            first = false;
        }
    }
    CHECK(largest < 1.1 * maxStep, "largest step %.5f, a click-free tone allows %.5f", largest, maxStep);
}

static void testFadeOutEndsInSilence() {
    std::printf("fade-out ends in silence\n");
    Engine eng;
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_start(eng.e, 4.0, 0.0, 3.0);
    const auto x = render(eng.e, kRate * 4);
    auto window = [&](double t) { return rms(x, size_t(t * kRate), size_t((t + 0.1) * kRate)); };

    const double full = window(0.4);
    CHECK(window(1.6) < full && window(2.2) < window(1.6) && window(2.8) < window(2.2) &&
              window(3.4) < window(2.8),
          "level should fall throughout the fade");
    CHECK(window(3.85) < full * 0.01, "last 150 ms should be below -40 dB (%.1f dB)",
          toDb(window(3.85) / full));
    CHECK(soundingFrames(x) <= int64_t(4 * kRate), "nothing after the end");
}

static void testShortSessionShrinksBothFades() {
    std::printf("short session shrinks both fades to fit\n");
    // 13 s with a 5 s fade-in and 60 s fade-out: 65 s of fades scale by 13/65
    // to a 1 s fade-in and a 12 s fade-out, so full level is reached at 1 s.
    Engine eng;
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_start(eng.e, 13.0, 5.0, 60.0);
    const auto x = render(eng.e, kRate * 13);
    auto window = [&](double t) { return rms(x, size_t(t * kRate), size_t((t + 0.05) * kRate)); };
    CHECK(std::fabs(toDb(window(0.975) / kBedRms)) < 1.0, "level at 1 s is %.1f dB from full",
          toDb(window(0.975) / kBedRms));
    CHECK(window(0.3) < window(0.6) && window(0.6) < window(0.9), "level should rise to 1 s");
    CHECK(window(4.0) < window(1.2) && window(10.0) < window(4.0), "level should fall after 1 s");
    CHECK(soundingFrames(x) <= int64_t(13 * kRate), "nothing after the end");
}

static void testFadeInIsSmooth() {
    std::printf("fade-in rises from silence\n");
    Engine eng;
    humspan_engine_set_volume(eng.e, 1.0f);
    humspan_engine_start(eng.e, 0.0, 2.0, 0.0);
    const auto x = render(eng.e, kRate * 3);
    auto window = [&](double t) { return rms(x, size_t(t * kRate), size_t((t + 0.05) * kRate)); };
    CHECK(window(0.0) < 0.01 * window(2.5), "first 50 ms should be near silence");
    CHECK(window(0.5) < window(1.0) && window(1.0) < window(1.5), "level should rise");
}

static void testStopFadesAndFinishes() {
    std::printf("stop fades out and finishes\n");
    Engine eng;
    humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    CHECK(humspan_engine_is_playing(eng.e), "infinite session should still be playing");
    humspan_engine_stop(eng.e, 0.5);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 2);
    CHECK(frames >= int64_t(0.5 * kRate) - kBlock && frames <= int64_t(0.5 * kRate) + kBlock,
          "stop took %lld frames, want about %d", (long long)frames, kRate / 2);
}

static void testNeverClips() {
    std::printf("output never reaches full scale\n");
    for (auto color : {HUMSPAN_NOISE_WHITE, HUMSPAN_NOISE_PINK, HUMSPAN_NOISE_BROWN}) {
        Engine eng(kRate, 7);
        humspan_engine_set_noise_color(eng.e, color);
        humspan_engine_set_volume(eng.e, 1.0f);
        humspan_engine_start(eng.e, 0.0, 0.0, 0.0);
        const auto x = render(eng.e, kRate * 30);
        float peak = 0;
        for (float s : x) peak = std::max(peak, std::fabs(s));
        CHECK(peak < 1.0f, "colour %d peak %.4f", color, peak);
    }
}

static void testRenderDoesNotAllocate() {
    std::printf("render does not allocate\n");
    Engine eng;
    std::vector<float> block(kBlock * 2);
    g_allocations = 0;
    g_trackAllocations = true;
    humspan_engine_start(eng.e, 30.0, 1.0, 5.0);
    for (int i = 0; i < 3000; ++i) {
        if (i % 200 == 0) humspan_engine_set_noise_color(eng.e, humspan_noise_color(i / 200 % 3));
        if (i % 300 == 0) humspan_engine_set_volume(eng.e, float(i % 7) / 7.0f);
        if (i == 100) humspan_engine_set_binaural(eng.e, 1);
        if (i == 150) humspan_engine_set_boom(eng.e, 1);
        if (i % 280 == 0) humspan_engine_set_boom_interval(eng.e, float(2 + (i / 280) % 3 * 2));
        if (i % 320 == 0) humspan_engine_set_speaker_output(eng.e, i / 320 % 2);
        if (i == 1300) humspan_engine_set_boom(eng.e, 0);
        if (i % 250 == 0) humspan_engine_set_beat_frequency(eng.e, float(2 + i / 250 % 5 * 2));
        if (i == 400) humspan_engine_set_duck_gain(eng.e, 0.3f);
        if (i == 600) humspan_engine_set_duck_gain(eng.e, 1.0f);
        if (i == 700) humspan_engine_pause(eng.e, 0.2);
        if (i == 900) humspan_engine_resume(eng.e, 1.0);
        if (i == 1200) humspan_engine_set_binaural(eng.e, 0);
        if (i == 1500) humspan_engine_stop(eng.e, 2.0);
        if (i == 2000) humspan_engine_start(eng.e, 5.0, 1.0, 1.0);
        if (i == 2100) humspan_engine_pause(eng.e, 0.2);
        if (i == 2105) humspan_engine_stop(eng.e, 1.0); // stop mid pause fade
        if (i == 2200) humspan_engine_start(eng.e, 5.0, 1.0, 1.0);
        if (i == 2500) humspan_engine_pause(eng.e, 0.1);
        if (i == 2700) humspan_engine_stop(eng.e, 1.0); // stop while paused
        if (i == 50) humspan_engine_set_noise(eng.e, 0);
        if (i == 120) humspan_engine_set_noise(eng.e, 1);
        if (i % 90 == 0) humspan_engine_set_noise_level(eng.e, float(i % 11) / 10.0f);
        if (i % 110 == 0) humspan_engine_set_binaural_level(eng.e, float(i % 13) / 12.0f);
        if (i % 130 == 0) humspan_engine_set_boom_level(eng.e, float(i % 9) / 8.0f);
        if (i == 1000) humspan_engine_set_noise(eng.e, 0); // all off mid-session
        if (i == 1100) humspan_engine_set_noise(eng.e, 1);
        humspan_engine_render(eng.e, block.data(), kBlock);
    }
    g_trackAllocations = false;
    CHECK(g_allocations == 0, "%d allocations during render", g_allocations.load());
}

int main() {
    testSpectralSlopeAndLevel();
    testDeterminism();
    testTimerIsFrameAccurate();
    testTimerSurvivesSampleRateChange();
    testRemainingSeconds();
    testPauseHoldsPlaceAndResumes();
    testStopWhilePausedEndsAtOnce();
    testStopDuringPauseFadeFinishes();
    testDuckLowersLevelAndKeepsClock();
    testBinauralBeatToneAndLevel();
    testBoomAlternatesEars();
    testBoomRetriggerIsSmooth();
    testSpeakerBoomStaysAboveTheSpeakerFloor();
    testEachLayerAlone();
    testNoiseToggleKeepsColorAndFades();
    testLayerLevels();
    testLevelChangesDoNotClick();
    testFadeOutEndsInSilence();
    testFadeInIsSmooth();
    testShortSessionShrinksBothFades();
    testStopFadesAndFinishes();
    testNeverClips();
    testRenderDoesNotAllocate();
    if (g_failures) {
        std::printf("%d check(s) failed\n", g_failures);
        return 1;
    }
    std::printf("all tests passed\n");
    return 0;
}
