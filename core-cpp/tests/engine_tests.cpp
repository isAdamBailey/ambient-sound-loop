// libambientsynth unit tests. Plain executable, no framework: each test
// returns normally or records a failure; main() exits non-zero on failure.
#include "ambient_engine.h"

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
    explicit Engine(uint32_t rate = kRate, uint64_t seed = 1) : e(ambient_engine_create(rate, seed)) {}
    ~Engine() { ambient_engine_destroy(e); }
    ambient_engine* e;
};

// Renders `frames` frames, returns interleaved stereo.
static std::vector<float> render(ambient_engine* e, int64_t frames, int* lastResult = nullptr) {
    std::vector<float> out(static_cast<size_t>(frames) * 2);
    int64_t done = 0;
    int result = 0;
    while (done < frames) {
        const int n = static_cast<int>(std::min<int64_t>(kBlock, frames - done));
        result = ambient_engine_render(e, out.data() + done * 2, n);
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
static int64_t renderUntilFinished(ambient_engine* e, int64_t limit, std::vector<float>* tail = nullptr) {
    std::vector<float> block(kBlock * 2);
    int64_t frames = 0;
    while (frames < limit) {
        const int r = ambient_engine_render(e, block.data(), kBlock);
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
    struct Case { ambient_noise_color color; const char* name; double slopeDbPerOctave; };
    const Case cases[] = {
        {AMBIENT_NOISE_WHITE, "white", 0.0},
        {AMBIENT_NOISE_PINK, "pink", -3.0},
        {AMBIENT_NOISE_BROWN, "brown", -6.0},
    };
    for (const auto& c : cases) {
        Engine eng;
        ambient_engine_set_noise_color(eng.e, c.color);
        ambient_engine_set_volume(eng.e, 1.0f);
        ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
        render(eng.e, kRate / 2); // let the colour/volume smoothing settle
        const auto x = render(eng.e, kRate * 20);

        const size_t n = 4096;
        const auto psd = averagedPsd(x, n);
        // 500-1000 Hz vs 4-8 kHz: three octaves apart.
        const double slope = 10.0 * std::log10(bandDensity(psd, 4000, 8000, n) / bandDensity(psd, 500, 1000, n)) / 3.0;
        CHECK(std::fabs(slope - c.slopeDbPerOctave) < 0.5, "%s slope %.2f dB/oct, want %.1f", c.name, slope,
              c.slopeDbPerOctave);

        // Every colour lands within 1 dB of the same RMS (0.18).
        const double level = toDb(rms(x, 0, x.size() / 2) / 0.18);
        CHECK(std::fabs(level) < 1.0, "%s level %.2f dB from target", c.name, level);
    }
}

static void testDeterminism() {
    std::printf("determinism\n");
    Engine a(kRate, 42), b(kRate, 42), c(kRate, 43);
    for (auto* e : {a.e, b.e, c.e}) ambient_engine_start(e, 0.0, 0.0, 0.0);
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
    ambient_engine_start(eng.e, 2.5, 0.0, 0.0);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 10);
    CHECK(frames == 120000, "2.5 s at 48 kHz rendered %lld frames, want 120000", (long long)frames);
    CHECK(!ambient_engine_is_playing(eng.e), "should report finished");
}

static void testTimerSurvivesSampleRateChange() {
    std::printf("timer survives a sample-rate change\n");
    Engine eng;
    ambient_engine_start(eng.e, 2.5, 0.0, 0.0);
    render(eng.e, 48000); // exactly 1.0 s at 48 kHz
    CHECK(std::fabs(ambient_engine_elapsed_seconds(eng.e) - 1.0) < 1e-9, "elapsed %.6f",
          ambient_engine_elapsed_seconds(eng.e));

    // Route change: the OS reopens the stream at 44.1 kHz.
    ambient_engine_set_sample_rate(eng.e, 44100);
    const int64_t frames = renderUntilFinished(eng.e, 44100 * 10);
    CHECK(frames == 66150, "remaining 1.5 s at 44.1 kHz rendered %lld frames, want 66150", (long long)frames);
}

static void testRemainingSeconds() {
    std::printf("remaining seconds\n");
    Engine eng;
    CHECK(ambient_engine_remaining_seconds(eng.e) == 0.0, "idle engine has nothing remaining");

    ambient_engine_start(eng.e, 10.0, 0.0, 0.0);
    render(eng.e, kRate * 4);
    CHECK(std::fabs(ambient_engine_remaining_seconds(eng.e) - 6.0) < 1e-9, "remaining %.6f, want 6",
          ambient_engine_remaining_seconds(eng.e));
    renderUntilFinished(eng.e, kRate * 10);
    CHECK(ambient_engine_remaining_seconds(eng.e) == 0.0, "finished session has nothing remaining");

    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    CHECK(ambient_engine_remaining_seconds(eng.e) < 0.0, "until-stopped session reports negative");
}

static void testPauseHoldsPlaceAndResumes() {
    std::printf("pause holds the session's place and resumes\n");
    Engine eng;
    ambient_engine_start(eng.e, 10.0, 0.0, 0.0);
    render(eng.e, kRate * 2);
    CHECK(!ambient_engine_is_paused(eng.e), "not paused before pause");

    ambient_engine_pause(eng.e, 0.1); // headphones out
    const auto fade = render(eng.e, kRate / 2);
    CHECK(rms(fade, 0, kRate / 50) > 0.0, "pause fades rather than cutting");
    CHECK(soundingFrames(fade) <= int64_t(0.1 * kRate), "silent after the 0.1 s pause fade");
    CHECK(ambient_engine_is_paused(eng.e) && ambient_engine_is_playing(eng.e), "paused session is still active");

    const auto held = render(eng.e, kRate * 3);
    CHECK(soundingFrames(held) == 0, "no output while paused");
    CHECK(std::fabs(ambient_engine_elapsed_seconds(eng.e) - 2.1) < 1e-4, "elapsed frozen at %.4f, want 2.1",
          ambient_engine_elapsed_seconds(eng.e));
    CHECK(std::fabs(ambient_engine_remaining_seconds(eng.e) - 7.9) < 1e-4, "remaining %.4f, want 7.9",
          ambient_engine_remaining_seconds(eng.e));

    ambient_engine_resume(eng.e, 0.5);
    const auto rise = render(eng.e, kRate);
    CHECK(!ambient_engine_is_paused(eng.e), "resumed");
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
    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    ambient_engine_pause(eng.e, 0.05);
    render(eng.e, kRate);
    ambient_engine_stop(eng.e, 1.0);
    int result = 1;
    render(eng.e, kBlock, &result);
    CHECK(result == 0 && !ambient_engine_is_playing(eng.e) && !ambient_engine_is_paused(eng.e),
          "stop from pause should finish in the next block");
}

static void testStopDuringPauseFadeFinishes() {
    std::printf("stop during a pause fade still finishes\n");
    Engine eng;
    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    ambient_engine_pause(eng.e, 0.2);
    render(eng.e, kRate / 10); // halfway through the pause fade
    ambient_engine_stop(eng.e, 1.0);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 5);
    CHECK(frames >= 0 && frames <= int64_t(1.0 * kRate) + kBlock, "session should end, took %lld frames",
          (long long)frames);
    CHECK(!ambient_engine_is_playing(eng.e) && !ambient_engine_is_paused(eng.e), "finished, not paused");
}

static void testDuckLowersLevelAndKeepsClock() {
    std::printf("duck lowers the level within 500 ms and keeps the clock\n");
    Engine eng;
    ambient_engine_set_volume(eng.e, 1.0f);
    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);

    ambient_engine_set_duck_gain(eng.e, 0.25f); // phone call: -12 dB
    const auto ducking = render(eng.e, kRate);
    auto window = [&](const std::vector<float>& x, double t) {
        return rms(x, size_t(t * kRate), size_t((t + 0.1) * kRate));
    };
    const double early = toDb(window(ducking, 0.0) / 0.18);
    const double settled = toDb(window(ducking, 0.5) / 0.18);
    CHECK(early > -9.0, "duck ramps rather than cutting (%.1f dB in first 100 ms)", early);
    CHECK(std::fabs(settled + 12.0) < 1.0, "ducked level %.1f dB, want -12 within 500 ms", settled);
    CHECK(std::fabs(ambient_engine_elapsed_seconds(eng.e) - 2.0) < 1e-9, "clock kept running: %.4f",
          ambient_engine_elapsed_seconds(eng.e));

    ambient_engine_set_duck_gain(eng.e, 1.0f);
    const auto restored = render(eng.e, kRate);
    CHECK(std::fabs(toDb(window(restored, 0.5) / 0.18)) < 1.0, "level back to full after the duck");
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
    // A sine with RMS kNoiseRms (0.18), 6 dB down: amplitude 0.18 * 0.5 * sqrt(2).
    const double want = 0.18 * 0.5 * std::numbers::sqrt2;
    Engine eng;
    ambient_engine_set_volume(eng.e, 1.0f);
    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate / 2);
    // Tones are measured over 8 s so pink noise's own projection onto them
    // (about 0.002, -36 dB re the tone) stays out of the way.
    const auto off = render(eng.e, kRate * 8);
    CHECK(toneAmplitude(off, 0, 180, 0, 8 * kRate) < 0.05 * want, "no tone while off");

    ambient_engine_set_binaural(eng.e, 1);
    ambient_engine_set_beat_frequency(eng.e, 4.0f);
    render(eng.e, kRate / 2); // let the layer fade in
    auto x = render(eng.e, kRate * 8);
    const double left = toneAmplitude(x, 0, 180, 0, 8 * kRate);
    const double right = toneAmplitude(x, 1, 184, 0, 8 * kRate);
    CHECK(std::fabs(toDb(left / want)) < 0.5, "left 180 Hz is %.2f dB from target", toDb(left / want));
    CHECK(std::fabs(toDb(right / want)) < 0.5, "right 184 Hz is %.2f dB from target", toDb(right / want));
    CHECK(toneAmplitude(x, 0, 184, 0, 8 * kRate) < 0.05 * want, "left has no 184 Hz");
    CHECK(toneAmplitude(x, 1, 180, 0, 8 * kRate) < 0.05 * want, "right has no 180 Hz");

    ambient_engine_set_beat_frequency(eng.e, 10.0f);
    render(eng.e, kRate / 2);
    x = render(eng.e, kRate * 8);
    CHECK(std::fabs(toDb(toneAmplitude(x, 1, 190, 0, 8 * kRate) / want)) < 0.5, "10 Hz beat puts right at 190 Hz");
    CHECK(std::fabs(toDb(toneAmplitude(x, 0, 180, 0, 8 * kRate) / want)) < 0.5, "carrier stays at 180 Hz");

    ambient_engine_set_volume(eng.e, 0.5f); // the beat follows the session volume
    render(eng.e, kRate / 2);
    x = render(eng.e, kRate * 8);
    CHECK(std::fabs(toDb(toneAmplitude(x, 0, 180, 0, 8 * kRate) / (0.5 * want))) < 0.5, "beat follows volume");

    ambient_engine_set_binaural(eng.e, 0);
    const auto fading = render(eng.e, kRate / 2);
    CHECK(toneAmplitude(fading, 0, 180, 0, kRate / 100) > 0.1 * 0.5 * want, "switching off fades, not cuts");
    x = render(eng.e, kRate * 8);
    CHECK(toneAmplitude(x, 0, 180, 0, 8 * kRate) < 0.05 * want, "no tone after switching off");
}

static void testFadeOutEndsInSilence() {
    std::printf("fade-out ends in silence\n");
    Engine eng;
    ambient_engine_set_volume(eng.e, 1.0f);
    ambient_engine_start(eng.e, 4.0, 0.0, 3.0);
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
    ambient_engine_set_volume(eng.e, 1.0f);
    ambient_engine_start(eng.e, 13.0, 5.0, 60.0);
    const auto x = render(eng.e, kRate * 13);
    auto window = [&](double t) { return rms(x, size_t(t * kRate), size_t((t + 0.05) * kRate)); };
    CHECK(std::fabs(toDb(window(0.975) / 0.18)) < 1.0, "level at 1 s is %.1f dB from full",
          toDb(window(0.975) / 0.18));
    CHECK(window(0.3) < window(0.6) && window(0.6) < window(0.9), "level should rise to 1 s");
    CHECK(window(4.0) < window(1.2) && window(10.0) < window(4.0), "level should fall after 1 s");
    CHECK(soundingFrames(x) <= int64_t(13 * kRate), "nothing after the end");
}

static void testFadeInIsSmooth() {
    std::printf("fade-in rises from silence\n");
    Engine eng;
    ambient_engine_set_volume(eng.e, 1.0f);
    ambient_engine_start(eng.e, 0.0, 2.0, 0.0);
    const auto x = render(eng.e, kRate * 3);
    auto window = [&](double t) { return rms(x, size_t(t * kRate), size_t((t + 0.05) * kRate)); };
    CHECK(window(0.0) < 0.01 * window(2.5), "first 50 ms should be near silence");
    CHECK(window(0.5) < window(1.0) && window(1.0) < window(1.5), "level should rise");
}

static void testStopFadesAndFinishes() {
    std::printf("stop fades out and finishes\n");
    Engine eng;
    ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
    render(eng.e, kRate);
    CHECK(ambient_engine_is_playing(eng.e), "infinite session should still be playing");
    ambient_engine_stop(eng.e, 0.5);
    const int64_t frames = renderUntilFinished(eng.e, kRate * 2);
    CHECK(frames >= int64_t(0.5 * kRate) - kBlock && frames <= int64_t(0.5 * kRate) + kBlock,
          "stop took %lld frames, want about %d", (long long)frames, kRate / 2);
}

static void testNeverClips() {
    std::printf("output never reaches full scale\n");
    for (auto color : {AMBIENT_NOISE_WHITE, AMBIENT_NOISE_PINK, AMBIENT_NOISE_BROWN}) {
        Engine eng(kRate, 7);
        ambient_engine_set_noise_color(eng.e, color);
        ambient_engine_set_volume(eng.e, 1.0f);
        ambient_engine_start(eng.e, 0.0, 0.0, 0.0);
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
    ambient_engine_start(eng.e, 30.0, 1.0, 5.0);
    for (int i = 0; i < 3000; ++i) {
        if (i % 200 == 0) ambient_engine_set_noise_color(eng.e, ambient_noise_color(i / 200 % 3));
        if (i % 300 == 0) ambient_engine_set_volume(eng.e, float(i % 7) / 7.0f);
        if (i == 100) ambient_engine_set_binaural(eng.e, 1);
        if (i % 250 == 0) ambient_engine_set_beat_frequency(eng.e, float(2 + i / 250 % 5 * 2));
        if (i == 400) ambient_engine_set_duck_gain(eng.e, 0.3f);
        if (i == 600) ambient_engine_set_duck_gain(eng.e, 1.0f);
        if (i == 700) ambient_engine_pause(eng.e, 0.2);
        if (i == 900) ambient_engine_resume(eng.e, 1.0);
        if (i == 1200) ambient_engine_set_binaural(eng.e, 0);
        if (i == 1500) ambient_engine_stop(eng.e, 2.0);
        if (i == 2000) ambient_engine_start(eng.e, 5.0, 1.0, 1.0);
        if (i == 2100) ambient_engine_pause(eng.e, 0.2);
        if (i == 2105) ambient_engine_stop(eng.e, 1.0); // stop mid pause fade
        if (i == 2200) ambient_engine_start(eng.e, 5.0, 1.0, 1.0);
        if (i == 2500) ambient_engine_pause(eng.e, 0.1);
        if (i == 2700) ambient_engine_stop(eng.e, 1.0); // stop while paused
        ambient_engine_render(eng.e, block.data(), kBlock);
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
