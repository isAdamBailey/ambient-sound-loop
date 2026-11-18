// ambient_player — engine plus miniaudio output stream for the app.
// See ambient_player.h for the threading contract.
#include "ambient_player.h"

#include "miniaudio.h"

#include <atomic>
#include <new>

struct ambient_player {
    ma_context context{};
    ma_device device{};
    bool deviceInitialised = false; // control thread only
    ambient_engine* engine = nullptr;
    std::atomic<uint32_t> events{0};
    bool lastActive = false; // audio thread only
};

namespace {

constexpr uint32_t kInitialSampleRate = 48000; // replaced by the device's rate on open

void dataCallback(ma_device* device, void* output, const void*, ma_uint32 frames) {
    auto* player = static_cast<ambient_player*>(device->pUserData);
    const bool active =
        ambient_engine_render(player->engine, static_cast<float*>(output), static_cast<int32_t>(frames)) != 0;
    if (player->lastActive && !active) {
        player->events.fetch_or(AMBIENT_PLAYER_EVENT_FINISHED, std::memory_order_release);
    }
    player->lastActive = active;
}

void notificationCallback(const ma_device_notification* notification) {
    auto* player = static_cast<ambient_player*>(notification->pDevice->pUserData);
    switch (notification->type) {
    case ma_device_notification_type_rerouted:
        player->events.fetch_or(AMBIENT_PLAYER_EVENT_REROUTED, std::memory_order_release);
        break;
    case ma_device_notification_type_interruption_began:
        player->events.fetch_or(AMBIENT_PLAYER_EVENT_INTERRUPTION_BEGAN, std::memory_order_release);
        break;
    case ma_device_notification_type_interruption_ended:
        // iOS: Core Audio stopped the stream for the call. Restart it here, on
        // the notification's main-thread callback, so the session continues
        // from where its timer stood even while the app's UI is suspended.
        if (ambient_engine_is_playing(player->engine)) {
            ma_device_start(notification->pDevice);
        }
        player->events.fetch_or(AMBIENT_PLAYER_EVENT_INTERRUPTION_ENDED, std::memory_order_release);
        break;
    default:
        break;
    }
}

} // namespace

extern "C" {

ambient_player* ambient_player_create(uint64_t seed) {
    auto* player = new (std::nothrow) ambient_player();
    if (!player) return nullptr;

    ma_context_config contextConfig = ma_context_config_init();
    // iOS: play in the background and with the silent switch on.
    contextConfig.coreaudio.sessionCategory = ma_ios_session_category_playback;
    contextConfig.coreaudio.sessionCategoryOptions = 0;
    if (ma_context_init(nullptr, 0, &contextConfig, &player->context) != MA_SUCCESS) {
        delete player;
        return nullptr;
    }
    player->engine = ambient_engine_create(kInitialSampleRate, seed);
    if (!player->engine) {
        ma_context_uninit(&player->context);
        delete player;
        return nullptr;
    }
    return player;
}

void ambient_player_destroy(ambient_player* player) {
    if (!player) return;
    ambient_player_close(player);
    ambient_engine_destroy(player->engine);
    ma_context_uninit(&player->context);
    delete player;
}

ambient_engine* ambient_player_engine(ambient_player* player) {
    return player ? player->engine : nullptr;
}

int ambient_player_open(ambient_player* player) {
    if (!player) return 0;
    if (!player->deviceInitialised) {
        ma_device_config config = ma_device_config_init(ma_device_type_playback);
        config.playback.format = ma_format_f32;
        config.playback.channels = 2;
        config.sampleRate = 0; // the device's native rate: no resampling
        config.performanceProfile = ma_performance_profile_conservative; // long sessions: favour battery
        config.dataCallback = dataCallback;
        config.notificationCallback = notificationCallback;
        config.pUserData = player;
        config.aaudio.usage = ma_aaudio_usage_media;
        config.aaudio.contentType = ma_aaudio_content_type_music;
        // Android: never move to the speaker by itself after headphones go.
        config.aaudio.noAutoStartAfterReroute = MA_TRUE;
        if (ma_device_init(&player->context, &config, &player->device) != MA_SUCCESS) {
            return 0;
        }
        player->deviceInitialised = true;
        // The stream is stopped, so changing the rate cannot race render.
        ambient_engine_set_sample_rate(player->engine, player->device.sampleRate);
    }
    if (ma_device_is_started(&player->device)) return 1;
    return ma_device_start(&player->device) == MA_SUCCESS ? 1 : 0;
}

void ambient_player_close(ambient_player* player) {
    if (!player || !player->deviceInitialised) return;
    ma_device_uninit(&player->device); // stops the stream first
    player->deviceInitialised = false;
    player->lastActive = false;
}

int ambient_player_is_running(const ambient_player* player) {
    if (!player || !player->deviceInitialised) return 0;
    return ma_device_is_started(&player->device) ? 1 : 0;
}

uint32_t ambient_player_take_events(ambient_player* player) {
    if (!player) return 0;
    return player->events.exchange(0, std::memory_order_acq_rel);
}

} // extern "C"
