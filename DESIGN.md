---
name: Humspan
description: One session screen for long procedural ambient sound, read like a tide table at night.
colors:
  ground: "#05090D"
  ink: "#D6CCB2"
  dim: "#8C8676"
  rule: "#1A232B"
  sea: "#4F7F95"
  sea-deep: "#1D3A4A"
  sea-wash: "#1D3A4A33"
  state: "#E0A85C"
  raised: "#0B1117"
typography:
  clock:
    fontFamily: "Atkinson Hyperlegible Mono"
    fontSize: "52px"
    fontWeight: 200
    lineHeight: 1
    letterSpacing: "-0.02em"
    fontFeature: "tnum"
  title:
    fontFamily: "Atkinson Hyperlegible Next"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.25
  option:
    fontFamily: "Atkinson Hyperlegible Next"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.25
  figures:
    fontFamily: "Atkinson Hyperlegible Mono"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.25
    fontFeature: "tnum"
  body:
    fontFamily: "Atkinson Hyperlegible Next"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.25
  note:
    fontFamily: "Atkinson Hyperlegible Next"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "Atkinson Hyperlegible Next"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0.08em"
rounded:
  option: "8px"
  field: "12px"
  key: "14px"
  dialog: "20px"
  sheet: "24px"
  pill: "14px"
spacing:
  target: "44px"
  gutter: "20px"
  row-gap: "10px"
  wide-gutter: "32px"
  wide-column-gap: "64px"
components:
  play-button:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    size: "68px"
  play-button-playing:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    size: "68px"
  layer-switch-on:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    rounded: "{rounded.pill}"
    width: "46px"
    height: "28px"
  layer-switch-off:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.dim}"
    rounded: "{rounded.pill}"
    width: "46px"
    height: "28px"
  word-option:
    textColor: "{colors.dim}"
    typography: "{typography.option}"
    rounded: "{rounded.option}"
    height: "{spacing.target}"
  word-option-chosen:
    textColor: "{colors.ink}"
    typography: "{typography.option}"
    rounded: "{rounded.option}"
    height: "{spacing.target}"
  stepper-button:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    size: "36px"
  exact-sheet:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sheet}"
    padding: "12px 20px 28px"
  keypad-key:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.key}"
    height: "52px"
  length-field:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    width: "96px"
---

# Design System: Humspan

## Overview

**Creative North Star: "The Night Tide Table"**

Humspan is one screen read half-awake in a dark room. A session is a span on a time scale: a round 12-hour dial shows the length as a sea-blue arc, the clock sits in its centre, and the time it ends is written underneath like a tide entry. Below it, ruled rows list the three sound layers as a table would, each with its own switch, its own control and its own level. Then one solid circle, Play. Once a session runs, the screen holds still except the clock and the draining arc.

The ground is near-black, the ink is warm parchment rather than white, and colour is spent by meaning: sea blue only for measured amounts, amber only for a change of state. Everything is flat. There are no gradients, glows, glass panels, cards or shadows; structure comes from hairline rules and from the tone of the ink. Each kind of job has its own form of control, so no single button style carries everything.

The world explicitly refuses the sleep-app category default: navy gradients, frosted glass cards and a wheel-picker timer. The same screen ships on Android, iOS and desktop; it does not take on Material or iOS styling per platform.

**Key Characteristics:**
- Near-black ground, parchment ink, one blue for amounts, one amber for state.
- Flat colour and hairline rules; no depth on the main screen.
- A round 12-hour length dial as the signature form.
- Atkinson Hyperlegible Next for words, its Mono for every figure.
- One control form per job: switch, underlined word, stepper, slider.
- Every touch target at least 44 px; fits a phone without scrolling.

## Colors

A night palette: two warm inks on a cold near-black, with two accents that each mean one thing.

### Primary
- **Parchment Ink** (`ink`): all primary text, the chosen option and its underline, slider thumbs, the dial handle, the on-switch track and the Play fill, the screen's one solid shape. About 12:1 on the ground.

### Secondary
- **Night Sea** (`sea`): measured amounts only. The dial's length arc and the filled part of each level slider. Never text, never a button fill.
- **Deep Sea** (`sea-deep`) and **Sea Wash** (`sea-wash`, Deep Sea at 20%): press, focus and selection washes, the slider's touch overlay. Feedback surfaces, never resting colour.

### Tertiary
- **Lamp Amber** (`state`): state changes only. Today that is the paused status ("Headphones disconnected. Paused.") and its icon.

### Neutral
- **Night Ground** (`ground`): the screen, the off-switch track, the Play glyph and the dial handle's centre dot.
- **Raised Night** (`raised`): the exact-length sheet and dialog, and their text fields. The only surface lighter than the ground.
- **Faded Ink** (`dim`): secondary text (control names, notes, the "ends" line, percentages), headings and controls of a layer that is off, unchosen options, stepper rings and the disabled stepper glyph, and the dial ring past 12 hours. About 5.4:1 on the ground.
- **Hairline** (`rule`): rules between layer rows, slider and dial tracks, the disabled stepper ring, keypad and field outlines, sheet edges.

### Named Rules
**The Measured Blue Rule.** Sea blue marks an amount on a scale (a length, a level) and nothing else. If it is not measuring, it is not blue.

**The Amber Alarm Rule.** Amber appears only when the session's state changed without the listener's hand. A screen at rest has no amber on it.

**The Parchment Rule.** Text and marks are parchment (`ink`) or faded parchment (`dim`), never pure white. A layer that is off keeps its controls usable and drops only to the faded tone.

## Typography

**Body Font:** Atkinson Hyperlegible Next (variable, bundled)
**Label/Mono Font:** Atkinson Hyperlegible Mono (variable, bundled), always with tabular figures

**Character:** A legibility face chosen for tired eyes, paired with its own mono so every number reads like an entry in a table. Weights are driven through the variable axis, so the clock can sit at a thin 200.

### Hierarchy
- **Clock** (Mono 200, 17% of the dial clamped to 30–52 px, line-height 1, -0.02em): the clock in the dial; also the keypad readout at 36 px with no tracking. Faded while paused.
- **Title** (600, 17 px): the exact-length sheet heading; Done uses 600 at 16 px.
- **Option** (400, 16 px): word choices (White, Pink, Brown) and sheet actions. Boom gaps use Mono at 16 px.
- **Stepper value** (Mono 400, 17 px): the beat frequency between − and +.
- **Body** (400, 15 px, faded): standalone messages such as "Audio is unavailable".
- **Note** (400, 14 px, line-height 1.4, faded): the dial caption, the "ends" line and the line beside Play. Control names ("Color", "Beat", "Every") also sit at 14 px faded.
- **Figures** (Mono 400, 13–14 px): preset stops, end times, slider percentages (13 px, -0.5 px tracking).
- **Label** (500, 12 px, 0.08em, uppercase): layer headings (NOISE, BINAURAL BEAT, BOOM). Ink when the layer is on, faded when off.

### Named Rules
**The Figures Are Mono Rule.** Any duration, frequency, percentage or time is set in the Mono with tabular figures; words around it stay in the Next.

**The Heading Means a Layer Rule.** Uppercase tracked labels name a sound layer row and carry its on/off tone. They are not decorative eyebrows and do not go above other content.

## Layout

A single column on phones: dial, preset stops, three ruled layer rows, then Play pinned to the bottom. The side gutter is 20 px (12 px top, 20 px bottom). The dial takes what the rows leave (screen height minus 590 px, clamped to 176–260 px), so a phone fits the whole screen without scrolling; a scroll view catches anything shorter. A flexible gap pushes the Play row down.

At 900 px and wider the screen becomes two columns inside a 940 px maximum width with a 32 px margin: a 340 px column holding a 300 px dial and the stops, a 64 px gap, then the layers and Play (28 px above Play).

Each layer row is a hairline rule on top, then three lines each 44 px tall: heading with its switch, the control name with its control right-aligned, and the level slider with its percentage in a 48 px column. Preset stops share the width equally so all six fit at any phone size.

**The Forty-Four Rule.** Every touch target is at least 44 × 44 px, including words and stops; their visible mark may be smaller.

## Elevation & Depth

The main screen is completely flat: no shadows, no elevation, no gradients, no blur. Separation comes from hairline rules and the tone of the ink. Slider thumbs carry zero elevation, even pressed. The one layered surface is exact entry: a bottom sheet (phone) or dialog (wide) in Raised Night over a 70% black scrim, outlined with a hairline, still without a shadow.

**The Flat Night Rule.** Depth is tone and line, never shadow or glow. A new surface is a step lighter (`raised`) and outlined with a hairline.

## Shapes

Circles and hairlines. The dial, the Play button, stepper rings, switch thumbs and slider thumbs are circles; the switch track is a full pill. Rules and tracks are thin: 1 px row rules, 2 px slider tracks, a 10 px dial ring, 1.5 px control outlines. Rectangles are rare and softly rounded by size: 8 px on option press areas, 12 px on fields and notices, 14 px on keypad keys, 20 px on the wide dialog, 24 px on the sheet's top corners. Choice is shown by a flat 2 px underline, not a box.

## Components

### Play / Stop
The screen's one solid shape. A 68 px circle filled with parchment and a ground-coloured play glyph (38 px). While playing it turns into a 1.5 px parchment ring with a stop glyph (30 px). Disabled: hairline ring, faded glyph, and the note reads "Turn on a sound to play." To its right a two-line note says what plays and for how long.

### Length Dial (signature)
A round 12-hour face. A 10 px hairline track with twelve hour ticks just inside it (quarters 12 px long, others 7 px), a sea-blue arc from 12 o'clock for the length, and a 22 px parchment handle with a 6 px ground dot at its end. Dragging on the ring band moves it in 5-minute steps with a haptic click at each hour; the centre does not respond to drags. Past 12 hours the whole ring turns faded; Until I stop is a full ring with no handle. While a session runs the dial locks, the handle disappears and the arc drains toward 12, redrawing once a minute. The centre holds the clock, a caption, "ends" plus the end time in Mono, and an underlined "Exact" link while stopped.

### Layer Switch
A 46 × 28 pill in a 56 × 44 target. On: parchment track, ground thumb at the right. Off: ground track with a 1.5 px faded outline and a faded thumb at the left. Moves over 160 ms, ease-out cubic.

### Word Choice and Preset Stops
Words in a row; the chosen one is parchment with a 2 px parchment underline (28 px wide, 24 px for stops), the rest faded. When the layer is off every word is faded but stays usable. Presses show a Deep Sea wash, no ripple. The Until I stop stop uses an infinity icon.

### Value Stepper
− and + in 36 px rings of Faded Ink inside 44 px targets, with the value in Mono 17 px between them in a 68 px column. The button at either end of the range disables: its ring drops to the hairline and its glyph to Faded Ink, so it stays readable but plainly loses its outline.

### Level Slider
A 2 px track: sea-blue fill, hairline remainder, an 8 px-radius parchment thumb, a Sea Wash touch overlay. When the layer is off the fill and thumb fade. The percentage sits right-aligned in Mono 13 px.

### Exact Length Sheet
On phones a bottom sheet in Raised Night: Cancel (faded) and Done (parchment, 600) flank the "Session length" title, a 36 px Mono readout, and a 3-column keypad of 52 px keys outlined in hairline with 14 px corners. On wide screens a dialog with three 96 px outlined fields (hairline at rest, parchment on focus) labelled in the uppercase label style. A refusal message appears in a hairline-outlined box.

### Paused Status
Replaces the preset stops while headphones are out: an amber headset icon and "Headphones disconnected. Paused." in amber 14 px/500, announced as a live region.

## Do's and Don'ts

### Do:
- **Do** keep the screen to ground, parchment and faded parchment, with sea blue only on the dial arc and level fills.
- **Do** give each new kind of job its own control form (switch, underlined word, stepper, slider) rather than reusing one button style.
- **Do** set every figure in Atkinson Hyperlegible Mono with tabular figures.
- **Do** keep every touch target at least 44 px and every text colour at 4.5:1 or better on the ground.
- **Do** dim an off layer to the faded tone while leaving its controls usable.
- **Do** separate rows with 1 px hairline rules, and new surfaces with the raised tone plus a hairline.

### Don't:
- **Don't** use navy gradients, glass or frosted cards, glows or a wheel-picker timer.
- **Don't** add shadows or elevation anywhere; slider thumbs and sheets stay flat.
- **Don't** use amber for anything but a state change the listener did not make.
- **Don't** use pure white text or bright fills; the brightest thing on screen is the parchment Play circle.
- **Don't** animate anything on the running screen beyond the clock and the draining arc.
- **Don't** adopt Material or iOS component styling per platform; the one design runs everywhere.
