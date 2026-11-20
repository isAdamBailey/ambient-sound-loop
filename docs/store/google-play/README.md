# Google Play

Main store listing fields for Play Console. The full description is the shared
one in [`../listing.md`](../listing.md) (4,000 characters max). Check limits in
Play Console on the day; they drift.

## App name (30 max)

Humspan: Noise & Binaural Beat

Alternative: `Humspan: Brown Noise & Beats` (28).

## Short description (80 max)

White, pink and brown noise, a binaural beat and a slow boom. It never loops.

## Category and tags

Music & Audio (not Health & Fitness). Up to five tags describing the sound, such as white noise or ambient.

## Release notes (1.0.0)

First release.

## Graphics

| File | Play field | Notes |
| --- | --- | --- |
| `icon-512.png` | App icon | 512×512 32-bit PNG from `app-ui/assets/icon/humspan-icon.svg`; Play applies the mask. |
| `feature-graphic-1024x500.png` | Feature graphic | Wordmark and dial in the `DESIGN.md` palette. |
| `phone-1-stopped.png` | Phone screenshot | Layers mixed, 8h selected. |
| `phone-2-playing.png` | Phone screenshot | Session running. |
| `phone-3-until-i-stop.png` | Phone screenshot | Until I stop selected. |
| `phone-4-lock-screen.png` | Phone screenshot | Lock-screen media controls. |

Screenshots are 1080×2400 from the `humspan_phone`-class emulator with Android demo mode on
(`adb shell settings put global sysui_demo_allowed 1`, then the `com.android.systemui.demo`
broadcasts for clock, battery, network and notifications) so the status bar is clean.
