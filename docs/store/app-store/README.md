# App Store

App Store Connect fields for Humspan (iOS and macOS share one app record,
bundle id `io.adambailey.humspan`). Check limits in App Store Connect on the
day; they drift. Every field follows the no-claims rule in
[`../listing.md`](../listing.md).

## App Information (set once)

| Field | Value |
| --- | --- |
| Name (30) | Humspan |
| Subtitle (30) | Noise, Binaural Beat & Boom |
| Primary category | Music (no secondary) |
| Content rights | Does not contain, show or access third-party content |
| Age rating | None/No to every item, unrestricted web access No: 4+ |
| SKU | humspan-ios |

## App Privacy

Privacy Policy URL `https://humspan.adambailey.io/privacy/`. Data collection:
"No, we do not collect data from this app" (Data Not Collected). True only
while the app has no networking, analytics or crash SDK.

## Pricing and Availability

Free, all countries (EU trader status: non-trader, set on the account).
iPhone/iPad apps on Apple silicon Macs: off. Apple Vision Pro: off.

## Version page (1.0)

**Promotional text (170):**

Colored noise, a binaural beat and a slow boom, generated live for any length you choose. It never loops.

**Description (4,000):** the shared text in `../listing.md` with two changes,
so it is true on iOS:

- "Lock-screen and notification controls" becomes "Lock Screen and Control Center controls".
- "leaves your phone" becomes "leaves your device".

**Keywords (100, comma-separated, no spaces):** words already in the name or
subtitle (humspan, noise, binaural, beat, boom) are indexed anyway, so they are
not repeated.

white,pink,brown,colored,ambient,generator,timer,offline,tone,hum,drone,stereo,mono,headphones

| Field | Value |
| --- | --- |
| Support URL | https://humspan.adambailey.io/support/ |
| Marketing URL | https://humspan.adambailey.io/ |
| Copyright | 2026 Adam Bailey |
| Version release | Manually release this version |

## Screenshots

| Set | Simulator | Size | Files |
| --- | --- | --- | --- |
| iPhone with Dynamic Island (large) | iPhone 18 Pro Max | 1320×2868 | `iphone-1-stopped.png` … `iphone-4-exact.png` |
| iPhone with Dynamic Island (medium) | iPhone 18 Pro | 1206×2622 | `iphone-medium-1-stopped.png` … `iphone-medium-4-exact.png` |
| iPad 13" | iPad Pro 13-inch (M5) | 2064×2752 | `ipad-1-stopped.png` … `ipad-4-exact.png` |

Order: (1) stopped, layers mixed, 8h; (2) playing; (3) Until I stop; (4) Exact
entry. The real app, driven by `app-ui/test_driver/store_screenshots*.dart`,
which seeds a fixed mix, taps through the screen and captures each state with
`simctl` so the overridden status bar is included. To remake a set (from
`app-ui/`, with the Simulator `$U` booted):

```bash
xcrun simctl status_bar $U override --time 9:41 --batteryState charged \
  --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ''
SHOTS_DEVICE=$U SHOTS_DIR=$PWD/../docs/store/app-store SHOTS_PREFIX=iphone \
  flutter drive -d $U --target=test_driver/store_screenshots.dart \
  --driver=test_driver/store_screenshots_test.dart
```

Use `SHOTS_PREFIX=iphone-medium` on the iPhone 18 Pro and `SHOTS_PREFIX=ipad`
on the iPad Pro 13-inch (portrait stacks like a phone, so it uses the keypad).
`SHOTS_WIDE=1` is only for a landscape set, where exact entry is typed fields.
Apple rejects screenshots with an alpha channel, so flatten each one:
`magick <file> -alpha off <file>`. The Simulator runs a debug build; the
screen is the same as release.
