// ambient_play — miniaudio desktop harness for libambientsynth.
//
//   ambient_play [--color white|pink|brown] [--duration 1h37m] [--fade-in 5]
//                [--fade-out 60] [--volume 0.5]
//
// Durations accept plain seconds ("90", "2.5") or h/m/s units ("1h37m15s").
// Without --duration it plays until Enter is pressed (with a 3 s fade).
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

#include "ambient_engine.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <thread>

namespace {

bool parseDuration(const char* text, double& seconds) {
    seconds = 0.0;
    const char* p = text;
    bool any = false;
    while (*p) {
        char* end = nullptr;
        const double value = std::strtod(p, &end);
        if (end == p || value < 0.0) return false;
        any = true;
        switch (*end) {
        case 'h': seconds += value * 3600.0; p = end + 1; break;
        case 'm': seconds += value * 60.0; p = end + 1; break;
        case 's': seconds += value; p = end + 1; break;
        case '\0': seconds += value; p = end; break;
        default: return false;
        }
    }
    return any;
}

void usage() {
    std::fprintf(stderr,
                 "usage: ambient_play [--color white|pink|brown] [--duration 1h37m]\n"
                 "                    [--fade-in SECONDS] [--fade-out SECONDS] [--volume 0..1]\n");
}

void dataCallback(ma_device* device, void* output, const void*, ma_uint32 frames) {
    auto* engine = static_cast<ambient_engine*>(device->pUserData);
    ambient_engine_render(engine, static_cast<float*>(output), static_cast<int32_t>(frames));
}

std::string clock(double seconds) {
    const long s = static_cast<long>(seconds);
    char buf[32];
    std::snprintf(buf, sizeof buf, "%02ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60);
    return buf;
}

} // namespace

int main(int argc, char** argv) {
    ambient_noise_color color = AMBIENT_NOISE_PINK;
    double duration = 0.0, fadeIn = 5.0, fadeOut = 60.0;
    float volume = 0.5f;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        const char* value = i + 1 < argc ? argv[i + 1] : nullptr;
        auto need = [&]() {
            if (!value) { usage(); std::exit(2); }
            ++i;
            return value;
        };
        if (arg == "--color") {
            const std::string c = need();
            if (c == "white") color = AMBIENT_NOISE_WHITE;
            else if (c == "pink") color = AMBIENT_NOISE_PINK;
            else if (c == "brown" || c == "red") color = AMBIENT_NOISE_BROWN;
            else { usage(); return 2; }
        } else if (arg == "--duration" || arg == "--fade-in" || arg == "--fade-out") {
            double seconds;
            if (!parseDuration(need(), seconds)) { usage(); return 2; }
            (arg == "--duration" ? duration : arg == "--fade-in" ? fadeIn : fadeOut) = seconds;
        } else if (arg == "--volume") {
            volume = static_cast<float>(std::atof(need()));
        } else {
            usage();
            return arg == "--help" || arg == "-h" ? 0 : 2;
        }
    }

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate = 0; // the device's native rate: no resampling
    config.dataCallback = dataCallback;

    // Create the engine once the device's real rate is known.
    ma_device device;
    config.pUserData = nullptr;
    if (ma_device_init(nullptr, &config, &device) != MA_SUCCESS) {
        std::fprintf(stderr, "could not open an audio device\n");
        return 1;
    }
    ambient_engine* engine = ambient_engine_create(device.sampleRate, static_cast<uint64_t>(std::time(nullptr)));
    device.pUserData = engine;

    ambient_engine_set_noise_color(engine, color);
    ambient_engine_set_volume(engine, volume);
    ambient_engine_start(engine, duration, fadeIn, fadeOut);

    if (ma_device_start(&device) != MA_SUCCESS) {
        std::fprintf(stderr, "could not start the audio device\n");
        ma_device_uninit(&device);
        ambient_engine_destroy(engine);
        return 1;
    }

    std::printf("Playing at %u Hz on \"%s\". %s\n", device.sampleRate, device.playback.name,
                duration > 0 ? ("Ends in " + clock(duration) + ".").c_str() : "Press Enter to stop.");

    std::atomic<bool> enterPressed{false};
    std::thread input([&] {
        // EOF (no terminal attached) is not a request to stop.
        if (std::getchar() != EOF) {
            enterPressed = true;
        }
    });
    input.detach();

    bool stopSent = false;
    // Give the audio thread a moment to pick up the start command.
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    while (ambient_engine_is_playing(engine)) {
        if (enterPressed && !stopSent) {
            ambient_engine_stop(engine, 3.0);
            stopSent = true;
            std::printf("\nFading out...\n");
        }
        const double elapsed = ambient_engine_elapsed_seconds(engine);
        if (duration > 0) {
            std::printf("\r%s remaining ", clock(duration - elapsed).c_str());
        } else {
            std::printf("\r%s elapsed ", clock(elapsed).c_str());
        }
        std::fflush(stdout);
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
    std::printf("\nFinished.\n");

    // Session over: release the device so the machine can idle.
    ma_device_uninit(&device);
    ambient_engine_destroy(engine);
    return 0;
}
