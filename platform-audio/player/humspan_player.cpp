// humspan_player — engine plus miniaudio output stream for the app.
// See humspan_player.h for the threading contract.
#include "humspan_player.h"

#include "miniaudio.h"

#include <atomic>
#include <new>

struct humspan_player {
    ma_context context{};
    ma_device device{};
    bool deviceInitialised = false; // control thread only
    humspan_engine* engine = nullptr;
    std::atomic<uint32_t> events{0};
    bool lastActive = false; // audio thread only
};

namespace {

constexpr uint32_t kInitialSampleRate = 48000; // replaced by the device's rate on open

void dataCallback(ma_device* device, void* output, const void*, ma_uint32 frames) {
    auto* player = static_cast<humspan_player*>(device->pUserData);
    const bool active =
        humspan_engine_render(player->engine, static_cast<float*>(output), static_cast<int32_t>(frames)) != 0;
    if (player->lastActive && !active) {
        player->events.fetch_or(HUMSPAN_PLAYER_EVENT_FINISHED, std::memory_order_release);
    }
    player->lastActive = active;
}

void notificationCallback(const ma_device_notification* notification);

// AAudio stream states. miniaudio only names these inside its implementation.
constexpr int kAAudioStarting = 3;
constexpr int kAAudioStarted = 4;

int aaudioPlaybackState(const humspan_player* player) {
#if defined(MA_SUPPORT_AAUDIO)
    using GetState = int32_t (*)(void*);
    auto getState = reinterpret_cast<GetState>(player->context.aaudio.AAudioStream_getState);
    void* stream = player->device.aaudio.pStreamPlayback;
    if (getState == nullptr || stream == nullptr) return -1;
    return getState(stream);
#else
    (void)player;
    return -1;
#endif
}

// requestStart can succeed and leave the stream running while miniaudio has
// already gone back to stopped (it bails if the state is not yet STARTING).
// The next start is then rejected. Treat a running stream as started.
bool adoptRunningStream(humspan_player* player) {
#if defined(MA_SUPPORT_AAUDIO)
    const int state = aaudioPlaybackState(player);
    if (state != kAAudioStarting && state != kAAudioStarted) return false;
    __atomic_store_n(reinterpret_cast<int*>(&player->device.state.value),
                     static_cast<int>(ma_device_state_started), __ATOMIC_SEQ_CST);
    return true;
#else
    (void)player;
    return false;
#endif
}

bool initDevice(humspan_player* player) {
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
        return false;
    }
    player->deviceInitialised = true;
    // The stream is stopped, so changing the rate cannot race render.
    humspan_engine_set_sample_rate(player->engine, player->device.sampleRate);
    return true;
}

void notificationCallback(const ma_device_notification* notification) {
    auto* player = static_cast<humspan_player*>(notification->pDevice->pUserData);
    switch (notification->type) {
    case ma_device_notification_type_rerouted:
        player->events.fetch_or(HUMSPAN_PLAYER_EVENT_REROUTED, std::memory_order_release);
        break;
    case ma_device_notification_type_interruption_began:
        player->events.fetch_or(HUMSPAN_PLAYER_EVENT_INTERRUPTION_BEGAN, std::memory_order_release);
        break;
    case ma_device_notification_type_interruption_ended:
        // iOS: Core Audio stopped the stream for the call. Restart it here, on
        // the notification's main-thread callback, so the session continues
        // from where its timer stood even while the app's UI is suspended.
        if (humspan_engine_is_playing(player->engine)) {
            ma_device_start(notification->pDevice);
        }
        player->events.fetch_or(HUMSPAN_PLAYER_EVENT_INTERRUPTION_ENDED, std::memory_order_release);
        break;
    default:
        break;
    }
}

} // namespace

extern "C" {

humspan_player* humspan_player_create(uint64_t seed) {
    auto* player = new (std::nothrow) humspan_player();
    if (!player) return nullptr;

    ma_context_config contextConfig = ma_context_config_init();
    // iOS: play in the background and with the silent switch on.
    contextConfig.coreaudio.sessionCategory = ma_ios_session_category_playback;
    contextConfig.coreaudio.sessionCategoryOptions = 0;
    if (ma_context_init(nullptr, 0, &contextConfig, &player->context) != MA_SUCCESS) {
        delete player;
        return nullptr;
    }
    player->engine = humspan_engine_create(kInitialSampleRate, seed);
    if (!player->engine) {
        ma_context_uninit(&player->context);
        delete player;
        return nullptr;
    }
    return player;
}

void humspan_player_destroy(humspan_player* player) {
    if (!player) return;
    humspan_player_close(player);
    humspan_engine_destroy(player->engine);
    ma_context_uninit(&player->context);
    delete player;
}

humspan_engine* humspan_player_engine(humspan_player* player) {
    return player ? player->engine : nullptr;
}

int humspan_player_open(humspan_player* player) {
    if (!player) return 0;
    if (!player->deviceInitialised && !initDevice(player)) return 0;
    if (ma_device_is_started(&player->device)) return 1;
    if (ma_device_start(&player->device) == MA_SUCCESS || adoptRunningStream(player)) return 1;

    // The stream is not running. Drop it and try once more.
    ma_device_uninit(&player->device);
    player->deviceInitialised = false;
    player->lastActive = false;
    if (!initDevice(player)) return 0;
    return ma_device_start(&player->device) == MA_SUCCESS || adoptRunningStream(player) ? 1 : 0;
}

void humspan_player_close(humspan_player* player) {
    if (!player || !player->deviceInitialised) return;
    ma_device_uninit(&player->device); // stops the stream first
    player->deviceInitialised = false;
    player->lastActive = false;
}

int humspan_player_is_running(const humspan_player* player) {
    if (!player || !player->deviceInitialised) return 0;
    return ma_device_is_started(&player->device) ? 1 : 0;
}

uint32_t humspan_player_take_events(humspan_player* player) {
    if (!player) return 0;
    return player->events.exchange(0, std::memory_order_acq_rel);
}

} // extern "C"
