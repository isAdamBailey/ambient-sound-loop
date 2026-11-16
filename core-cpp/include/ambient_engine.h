/*
 * ambient_engine.h — flat C ABI for libambientsynth.
 *
 * Threading contract:
 *   - ambient_engine_render() runs on the platform's real-time audio thread.
 *     It never allocates, locks, does I/O or throws.
 *   - Every other function is called from one control (UI) thread. Parameter
 *     setters write atomics; start/stop go through a lock-free SPSC queue, so
 *     they are safe to call while the audio thread is rendering.
 *   - ambient_engine_create/destroy and ambient_engine_set_sample_rate must NOT
 *     run concurrently with render (call them while the stream is stopped,
 *     e.g. when the OS reopens the stream after a route change).
 */
#ifndef AMBIENT_ENGINE_H
#define AMBIENT_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ambient_engine ambient_engine;

typedef enum ambient_noise_color {
    AMBIENT_NOISE_WHITE = 0, /* flat, 0 dB/octave      */
    AMBIENT_NOISE_PINK = 1,  /* -3 dB/octave           */
    AMBIENT_NOISE_BROWN = 2  /* -6 dB/octave (red)     */
} ambient_noise_color;

/* Create an engine for a stream running at `sample_rate` Hz. `seed` makes the
 * noise reproducible (tests); pass any value (e.g. time) in the app. Returns
 * NULL on invalid arguments or allocation failure. */
ambient_engine* ambient_engine_create(uint32_t sample_rate, uint64_t seed);
void ambient_engine_destroy(ambient_engine* engine);

/* The stream was reopened at a new rate (Bluetooth route change etc.). The
 * timer is kept in time, not samples, so a session's remaining duration is
 * unaffected. Not real-time safe with respect to render: see above. */
void ambient_engine_set_sample_rate(ambient_engine* engine, uint32_t sample_rate);

/* Continuous parameters (smoothed on the audio thread, no zipper noise). */
void ambient_engine_set_noise_color(ambient_engine* engine, ambient_noise_color color);
void ambient_engine_set_volume(ambient_engine* engine, float volume); /* clamped to [0, 1] */

/* Start a session. duration_seconds <= 0 plays until stopped. The fade-in is
 * a raised-cosine S-curve; the fade-out occupies the final fade_out_seconds of
 * the duration and ends in true silence. Restarting while playing begins a new
 * session from the current level. Returns 0 if the command queue is full. */
int ambient_engine_start(ambient_engine* engine, double duration_seconds,
                         double fade_in_seconds, double fade_out_seconds);

/* Fade to silence over fade_seconds from the current level, then finish.
 * Returns 0 if the command queue is full. */
int ambient_engine_stop(ambient_engine* engine, double fade_seconds);

/* Render `frames` frames of interleaved stereo float32 into `out`. Always
 * fills the whole buffer (silence when idle or finished). Returns 1 while a
 * session is active after this block, 0 once it has finished (the driver may
 * then close the stream so the device can idle). */
int ambient_engine_render(ambient_engine* engine, float* out, int32_t frames);

/* Rendered audio time of the current session, in seconds, and whether a
 * session is active. Safe from the control thread (atomics; may lag by one
 * audio buffer). */
double ambient_engine_elapsed_seconds(const ambient_engine* engine);
int ambient_engine_is_playing(const ambient_engine* engine);

#ifdef __cplusplus
}
#endif

#endif /* AMBIENT_ENGINE_H */
