/*
 * humspan_player.h — the app's native audio layer: one engine plus the
 * platform's audio output stream (miniaudio), behind a flat C ABI.
 *
 * The UI sets parameters and starts, stops, pauses and resumes sessions with
 * the humspan_engine.h functions on the engine returned by
 * humspan_player_engine(). This header only adds the output stream: opening it
 * when a session starts, closing it when the session ends so the device can
 * idle, and reporting what the device did (route changes, the end of the
 * session) for the UI to act on.
 *
 * Threading contract:
 *   - Every function here is called from the one control (UI) thread that also
 *     makes the humspan_engine.h control calls.
 *   - The output stream calls humspan_engine_render() on the real-time audio
 *     thread. Device notifications (route changes, interruptions) arrive on a
 *     system thread; they only set atomic flags, read back with
 *     humspan_player_take_events(). The one exception is the end of an iOS
 *     interruption (a phone call), which restarts the stream from the
 *     notification itself so the session continues without the UI running.
 */
#ifndef HUMSPAN_PLAYER_H
#define HUMSPAN_PLAYER_H

#include <stdint.h>

#include "humspan_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct humspan_player humspan_player;

/* Bits returned by humspan_player_take_events(). */
enum {
    /* The OS moved the stream to another output (default device changed,
     * headphones in or out). On Android the stream is left stopped after a
     * reroute so sound never moves to the speaker by itself; call
     * humspan_player_open() to restart it. Elsewhere it keeps running. */
    HUMSPAN_PLAYER_EVENT_REROUTED = 1,
    /* The session finished (render returned 0). Close the stream. */
    HUMSPAN_PLAYER_EVENT_FINISHED = 2,
    /* The OS stopped the stream for an interruption (iOS). */
    HUMSPAN_PLAYER_EVENT_INTERRUPTION_BEGAN = 4,
    /* The interruption ended and the stream was restarted (iOS). */
    HUMSPAN_PLAYER_EVENT_INTERRUPTION_ENDED = 8
};

/* Create a player and its engine. No stream is opened yet. `seed` seeds the
 * noise. Returns NULL if the audio system cannot be initialised. */
humspan_player* humspan_player_create(uint64_t seed);

/* Close the stream and destroy the engine. */
void humspan_player_destroy(humspan_player* player);

/* The engine to drive with the humspan_engine.h control functions. Owned by
 * the player; valid until humspan_player_destroy(). */
humspan_engine* humspan_player_engine(humspan_player* player);

/* Open the output stream at the device's native rate (setting the engine's
 * sample rate to match) and start it. If the stream is open but stopped (after
 * an Android reroute) it is restarted. Returns 1 if the stream is running. */
int humspan_player_open(humspan_player* player);

/* Stop and close the output stream so the device can idle. */
void humspan_player_close(humspan_player* player);

/* 1 while the output stream is open and running. */
int humspan_player_is_running(const humspan_player* player);

/* Events since the last call, as HUMSPAN_PLAYER_EVENT_* bits; clears them. */
uint32_t humspan_player_take_events(humspan_player* player);

#ifdef __cplusplus
}
#endif

#endif /* HUMSPAN_PLAYER_H */
