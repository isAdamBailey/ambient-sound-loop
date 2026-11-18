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

/* Duck the output for a phone call or system interruption: a gain in [0, 1]
 * (1 = no duck) on top of the volume, smoothed so it settles in about 500 ms.
 * The session and its timer carry on. Control thread (atomic). */
void ambient_engine_set_duck_gain(ambient_engine* engine, float gain);

/* Binaural beat: a stereo tone layer on top of the noise, a fixed 180 Hz
 * carrier in the left channel and 180 Hz + beat in the right. It follows the
 * session volume and envelope and sits 6 dB under the noise. Switching it on
 * or off is smoothed; changing the beat keeps phase, so neither clicks. Off by
 * default, beat 4 Hz. Control thread (atomics). */
void ambient_engine_set_binaural(ambient_engine* engine, int enabled);
void ambient_engine_set_beat_frequency(ambient_engine* engine, float beat_hz); /* clamped to [1, 30] Hz */

/* Start a session. duration_seconds <= 0 plays until stopped. The fade-in is
 * a raised-cosine S-curve; the fade-out occupies the final fade_out_seconds of
 * the duration and ends in true silence. Restarting while playing begins a new
 * session from the current level. Returns 0 if the command queue is full. */
int ambient_engine_start(ambient_engine* engine, double duration_seconds,
                         double fade_in_seconds, double fade_out_seconds);

/* Fade to silence over fade_seconds from the current level, then finish.
 * Returns 0 if the command queue is full. */
int ambient_engine_stop(ambient_engine* engine, double fade_seconds);

/* Pause the session (headphones out): fade to silence over fade_seconds from
 * the current level, then hold. While paused, render outputs silence and the
 * session timer stands still; the session stays active (render returns 1).
 * Stop while paused finishes at once. Ignored when idle, paused or stopping.
 * Control thread; goes through the command queue. Returns 0 if it is full. */
int ambient_engine_pause(ambient_engine* engine, double fade_seconds);

/* Resume a paused (or pausing) session from where its timer stood, rising
 * over fade_in_seconds. The timed fade-out still applies near the end.
 * Ignored unless pausing or paused. Control thread; goes through the command
 * queue. Returns 0 if it is full. */
int ambient_engine_resume(ambient_engine* engine, double fade_in_seconds);

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

/* 1 while the session is paused (pause fade finished, timer held). A paused
 * session also reports is_playing. Control thread (atomic; may lag by one
 * audio buffer). */
int ambient_engine_is_paused(const ambient_engine* engine);

/* Seconds left in a timed session (duration minus elapsed), for the clock and
 * the system now-playing position. Negative for a session that plays until
 * stopped; 0 when no session is active. Safe from the control thread
 * (atomics; may lag by one audio buffer). */
double ambient_engine_remaining_seconds(const ambient_engine* engine);

#ifdef __cplusplus
}
#endif

#endif /* AMBIENT_ENGINE_H */
