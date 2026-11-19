# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

Humspan is one Flutter session screen with one design language, the same on macOS, Windows, Linux, iOS and Android (`GLOSSARY.md`: "Session screen"). It does not adopt Material or iOS styling per OS. Native conventions apply only to system behaviour: now-playing and lock-screen controls, safe areas, back gestures, the foreground service and audio session. Android is the primary verified device; iOS and desktop share the same screen.

## Users

Primary: someone going to sleep. They are in bed, in the dark, usually on a phone. They set a sound and a long timer (often hours, or Until I stop), press Play, lock the screen and put the phone down. The interaction lasts seconds and happens half-awake, in a dark room. After that the product is the sound, not the screen.

Secondary (not designed for first): focus or relaxation sessions, including long desktop sessions.

## Product Purpose

Humspan plays ambient sound (colored noise, a binaural beat, a slow alternating boom) for any length, from minutes to days, with no audible loop point or repetition, because every sample is generated in real time. Success: the listener sets it once, sleeps, and the sound never clicks, loops, jumps to the speaker, or ends abruptly. A timed session fades out over its final minute and ends in true silence.

## Positioning

Most sleep apps loop a recorded 30–60 s file. Humspan's sound is procedural, rendered by a real-time C++ engine, so it cannot repeat, and a session can be any exact length (e.g. `1h 37m`). It deliberately makes no sleep, health or brainwave claims; binaural beats are offered as a sound, labelled by frequency only.

## Operating Context

- One screen, no accounts, no library of saved mixes. The **last session** settings are restored on launch, always stopped; the app never plays on launch.
- Used in the dark, then left alone with the screen locked. Lock-screen and now-playing controls (title "Humspan", subtitle naming the layers that are on) are part of the product surface.
- Loudness is the device volume; there is no master volume. Per-layer level sliders set only the mix.
- Headphones or Bluetooth disconnecting pauses the session and never routes sound to the speaker. Calls duck the audio and keep the clock.
- The app never dims itself and holds no wake lock.

## Capabilities and Constraints

- Shipped (spec #9, issues #10, #14, PR #17): Length dial holding the clock and the end time (12-hour face, 5-minute drag steps, locked while a session runs), preset stops (30m, 1h, 2h, 4h, 8h, Until I stop), exact h/m/s entry, Noise (White/Pink/Brown, on/off, level), Binaural beat (2–10 Hz stepper, on/off, level), Boom (8/4/2 s gap, alternates left and right, on/off, level), Play/Stop. Narrow stacked layout under 900 px; at 900 px and up the dial sits left of the layers.
- Terminology is fixed in `GLOSSARY.md` (Session, Session screen, Until I stop, Last session, Boom). UI copy uses US English.
- Out of scope for now (spec #9 §1): web/PWA, user-set fades, in-app dimming, master volume, isochronic tones, tone/warmth/width controls, recorded soundscapes, capture-and-extend, drones. PLAN.md lists them as possible later phases.
- Engine rules in `CLAUDE.md` (real-time safety, the C ABI as the only boundary, time not samples) constrain any feature a UI can expose.

## Brand Commitments

- Name: **Humspan** ("hum" for the sound, "span" for long sessions). Store listings keep the name and put search terms in the subtitle (e.g. "Humspan: Brown Noise & Binaural"). Bundle id `dev.humspan.app`.
- Voice: plain and factual. Labels name frequencies and gaps. No sleep, health, entrainment or "lucid" wording anywhere; that is why the earlier name "Ambient Lucidity" was dropped.
- Release target: the App Store and Google Play. Before release, confirm the name in App Store Connect and Google Play and run a USPTO (Class 9) search.

## Evidence on Hand

- Spec: GitHub issue #9; design history in issues #1–#8; mock-up at a private Claude canvas linked from #9.
- Device verification on an Android phone: lock-screen controls, headphone unplug, call duck, and a full `1h 37m` session.
- No testimonials, user research, reviews, download numbers, or sleep-outcome data exist. Do not invent them, and never make outcome claims.

## Product Principles

1. **Set once, then disappear.** Starting a session takes a few seconds; after that, nothing on screen should ask for attention.
2. **The sound must never startle.** No clicks, no loops, no sudden silence, no surprise speaker output. Every change is smoothed and every ending fades.
3. **Exact, not approximate.** Any duration the listener wants, kept in rendered audio time.
4. **No claims.** Describe what the sound is, never what it does to the listener.
5. **One screen, everywhere.** Same blocks, same order, same behaviour on every platform.

## Accessibility & Inclusion

- Text meets 4.5:1 contrast; touch targets are at least 44 px.
- Every control is a real button, slider or text field with a label. Level sliders are labelled per layer ("Noise level") and announce a percentage. Toggles expose pressed state. The clock is labelled and never announced as it ticks.
- Use in the dark, half-awake, is the main situation: avoid bright surfaces and small or fiddly targets.
