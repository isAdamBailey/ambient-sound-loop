# App Review notes

Pasted into App Store Connect → version page → App Review Information → Notes.
Written for guidelines 2.5.4 (background audio), 4.2/4.3 (minimum
functionality, spam) and 1.4.1 (health claims). Keep it true of the build
under review.

```
Humspan generates colored noise (white, pink, brown), a binaural beat and an alternating low "boom" procedurally, in real time, for any exact length the listener sets (for example 1h 37m 15s) or until stopped. No audio files are bundled and nothing loops. Each layer has its own level, and every change is smoothed.

Background audio (UIBackgroundModes: audio) is used only to keep a session the listener started playing while the screen is locked. Lock Screen and Control Center controls pause and stop it. If headphones disconnect, the session pauses rather than moving to the speaker. A timed session fades out over its last minute and ends in silence.

To test: press Play, then lock the device; the sound continues. Use the Lock Screen controls to pause. The binaural layer is meant for headphones.

On iPad the screen stacks in portrait and puts the dial beside the layers in landscape; it works in Split View, Slide Over and Stage Manager.

The app makes no health, sleep or medical claims, collects no data, has no account and makes no network requests. The only link (Privacy, beside Play) opens the privacy policy in Safari.
```

Sign-in required: No.
