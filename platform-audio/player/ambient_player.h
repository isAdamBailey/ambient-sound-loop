/*
 * ambient_player.h — the app's native audio layer: one engine plus the
 * platform's audio output stream (miniaudio), behind a flat C ABI.
 *
 * The UI sets parameters and starts, stops, pauses and resumes sessions with
 * the ambient_engine.h functions on the engine returned by
 * ambient_player_engine(). This header only adds the output stream: opening it
 * when a session starts, closing it when the session ends so the device can
 * idle, and reporting what the device did (route changes, the end of the
 * session) for the UI to act on.
 *
 * Threading contract:
 *   - Every function here is called from the one control (UI) thread that also
 *     makes the ambient_engine.h control calls.
 *   - The output stream calls ambient_engine_render() on the real-time audio
 *     thread. Device notifications (route changes, interruptions) arrive on a
 *     system thread; they only set atomic flags, read back with
 *     ambient_player_take_events(). The one exception is the end of an iOS
 *     interruption (a phone call), which restarts the stream from the
 *     notification itself so the session continues without the UI running.
 */
#ifndef AMBIENT_PLAYER_H
#define AMBIENT_PLAYER_H

#include <stdint.h>

#include "ambient_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ambient_player ambient_player;

/* Bits returned by ambient_player_take_events(). */
enum {
    /* The OS moved the stream to another output (default device changed,
     * headphones in or out). On Android the stream is left stopped after a
     * reroute so sound never moves to the speaker by itself; call
     * ambient_player_open() to restart it. Elsewhere it keeps running. */
    AMBIENT_PLAYER_EVENT_REROUTED = 1,
    /* The session finished (render returned 0). Close the stream. */
    AMBIENT_PLAYER_EVENT_FINISHED = 2,
    /* The OS stopped the stream for an interruption (iOS). */
    AMBIENT_PLAYER_EVENT_INTERRUPTION_BEGAN = 4,
    /* The interruption ended and the stream was restarted (iOS). */
    AMBIENT_PLAYER_EVENT_INTERRUPTION_ENDED = 8
};

/* Create a player and its engine. No stream is opened yet. `seed` seeds the
 * noise. Returns NULL if the audio system cannot be initialised. */
ambient_player* ambient_player_create(uint64_t seed);

/* Close the stream and destroy the engine. */
void ambient_player_destroy(ambient_player* player);

/* The engine to drive with the ambient_engine.h control functions. Owned by
 * the player; valid until ambient_player_destroy(). */
ambient_engine* ambient_player_engine(ambient_player* player);

/* Open the output stream at the device's native rate (setting the engine's
 * sample rate to match) and start it. If the stream is open but stopped (after
 * an Android reroute) it is restarted. Returns 1 if the stream is running. */
int ambient_player_open(ambient_player* player);

/* Stop and close the output stream so the device can idle. */
void ambient_player_close(ambient_player* player);

/* 1 while the output stream is open and running. */
int ambient_player_is_running(const ambient_player* player);

/* Events since the last call, as AMBIENT_PLAYER_EVENT_* bits; clears them. */
uint32_t ambient_player_take_events(ambient_player* player);

#ifdef __cplusplus
}
#endif

#endif /* AMBIENT_PLAYER_H */
