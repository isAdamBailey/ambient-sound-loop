# Humspan site (`site/`)

The marketing site in `site/`: a home page, `privacy/` and `support/`. Plain static files with no build step and no dependencies. Deploy by publishing the `site/` folder (no build command). The fonts are the app's own Atkinson Hyperlegible files, served from `site/assets/fonts/`, so the site loads nothing from third parties.

```bash
python3 -m http.server 8765 --directory site   # then open http://127.0.0.1:8765/
```

Serve it from the `site/` root; the pages link to each other with relative paths.

## Store submission

| Store field | URL |
| --- | --- |
| App Store Connect: Privacy Policy URL, Google Play: Privacy policy | https://humspan.adambailey.io/privacy/ |
| App Store Connect: Support URL | https://humspan.adambailey.io/support/ |
| App Store Connect: Marketing URL (optional) | https://humspan.adambailey.io/ |

The app's Privacy link (`app-ui/lib/src/ui/privacy.dart`) opens the privacy URL, so keep `site/privacy/` at that path.

The privacy policy states that the app collects no data, so the App Store privacy label is "Data Not Collected" and the Play Data safety form declares no data collected or shared. Keep all three in step.

## When the store listings go live

Each `.stores` list in `site/index.html` (in the hero and at the end) holds two `<span class="store is-soon">` placeholders. Replace each one with `<a class="store" href="…">` (or the official Apple and Google badge artwork, which their guidelines prefer). A live link is drawn as a solid parchment pill.

## Analytics

The site has none today. Before you add any, update the "This website" section of `site/privacy/index.html`, naming the provider and what it collects, and change the effective date. The app itself must never collect analytics; the policy promises that.
