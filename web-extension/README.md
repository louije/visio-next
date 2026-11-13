# Adaptive Meet participant strip

An adaptive layout tweak for [Meet / La Suite numérique](https://visio.numerique.gouv.fr)
(built on LiveKit). When a screen is shared, Meet's focus mode squeezes everyone
else into a **single vertical scrolling column**. A small engine instead reads the
shared content's real aspect ratio and lays the participants out:

- **Everyone visible** — tries the strip below and beside the content and keeps a
  layout that shows every participant at a legible size: 160×100 at least, or
  128×80 when that is what lets everyone fit. Tiles first grow into the grey
  letterbox bars; when those are too thin, the shared content shrinks (more grey
  bars) to make room, by at most three lines. Beside a narrow window (a tall Notion
  page) the strip may use more lines, as long as they stay in the grey band.
- **Content as large as possible** — among the layouts that show everyone, the one
  that leaves the shared content biggest, then the one with the biggest tiles.
- **Scroll from the start** — when no layout shows everyone, the strip keeps
  160×100 tiles in as many lines as it may take and scrolls along its length,
  starting at the first participant.

Two sources, shared by all targets:

- `enhance.css` — turns the engine's hooks into the grid. All rules are gated
  behind `.vn-on` on `<html>`, so the toolbar toggle can make them inert.
- `layout-engine.js` — measures + decides, writing `data-vn-place` / `--vn-lines` /
  `--vn-tile-w` / `--vn-tile-h` / `--vn-strip` onto `.lk-focus-layout` and toggling
  `.vn-on`. Its decision function is pure and unit-tested over 2–50 participants,
  several window sizes and shared-screen shapes (`layout-engine.test.cjs`).
- `layout-gallery.html` — the real CSS + engine on mocked Visio screen shares, one
  thumbnail per case: open it to eyeball the layouts. `layout-browser.test.cjs` runs
  it in headless Chromium/Chrome and checks every tile is reachable, sized and
  placed as decided (skipped when no browser is found; `$CHROMIUM` picks one).
  Run everything with `node --test`.

**On/off:** click the toolbar icon for a popup with an Enabled switch (default on).
The state is stored (`storage` permission) and applied live — no reload. The
bookmarklet has no toolbar, so it just toggles by re-clicking.

**Global mute (with the VisioNext app):** `call-bridge.js` reports each call's
microphone state to `background.js`, which keeps a native-messaging port to the app
while a call is live; the app's shortcut, menu bar mic or menu item sends back
`setMuted`. What a call looks like on each site is in `providers/`:
`visio.js` (Visio's `#media-state`, Ctrl+D), `meet.js` (`data-is-muted` + the
Material Symbols icon name, click) and `teams.js` (`data-track-action-scenario` /
`data-state`, click). Visio is always on; Google Meet and Teams are opt-in from the
options page (optional host permissions — the background registers their scripts). Chrome
needs the unpacked id pinned by `key` in `manifest.json`
(`fhbbknecepkblnbamdgflfjaakijkfhp`); the app registers the native host at launch.
Designs: `../docs/superpowers/specs/2026-09-29-global-mute-design.md`,
`../docs/superpowers/specs/2026-09-30-mute-meet-teams-design.md`.

## Design notes

See [`../docs/superpowers/specs/2026-11-13-layout-engine-fit-everyone-design.md`](../docs/superpowers/specs/2026-11-13-layout-engine-fit-everyone-design.md)
(which supersedes the decision rule of `2026-07-02-meet-adaptive-layout-engine-design.md`).
Tunables are constants in `layout-engine.js` (`minTileW` 160, `squeezeTileW` 128,
`maxLines` 3 — lines that may eat into the content, `maxFraction` 0.4 — how much of
the area the strip may take from the content),
overridable at runtime via `window.__vnMeet.config`.

> The grid CSS is checked in headless Chromium against LiveKit's stock CSS (see
> `layout-gallery.html`), not against Visio's own styles: check the running site
> after changing sections 2–4 of `enhance.css`.

## 1. Bookmarklet (any browser, zero install)

```sh
node build-bookmarklet.mjs
```

This writes `dist/bookmarklet.txt` (the `javascript:` one-liner) and
`dist/install.html`. Open `dist/install.html`, drag the button to your bookmarks
bar, then click it on `visio.numerique.gouv.fr` while a screen is shared. Click
again to toggle it off.

## 2. Chrome / Chromium (unpacked extension)

This folder **is** the extension.

1. `chrome://extensions` → enable **Developer mode**.
2. **Load unpacked** → select this `web-extension/` directory.

It injects `enhance.css` + `layout-engine.js` on `visio.numerique.gouv.fr`.
(Chrome logs a harmless "Unrecognized manifest key browser_specific_settings" —
that key is only for Firefox.)

## 3. Firefox

Same folder, same MV3 manifest (the Firefox add-on id lives in
`browser_specific_settings.gecko`).

- **Temporary (dev):** `about:debugging#/runtime/this-firefox` → **Load Temporary
  Add-on…** → pick this folder's `manifest.json`. Gone on restart.
- **Permanent:** submit `dist/web-extension.zip` to
  [addons.mozilla.org](https://addons.mozilla.org) for signing, or load the zip in
  Firefox Developer/Nightly with `xpinstall.signatures.required=false`.

## Packaging (Chrome Web Store / AMO)

```sh
node package.mjs   # -> dist/web-extension.zip (manifest + css + js)
```

One zip works for both stores; the Firefox id is baked into the manifest. Releases
(`Scripts/release.sh X.Y.Z`) submit it to both stores from GitHub Actions: see
`STORE.md`, "Automated publishing".

## 4. Safari (bundled with VisioNext.app)

The Safari Web Extension ships inside the VisioNext menu-bar app as the
`VisioSafariExtension` target (see `../App/project.yml`). It reuses the same
`manifest.json` + `enhance.css` + `layout-engine.js` from this folder.

```sh
cd ../App && xcodegen generate && open VisioNext.xcodeproj
```

Build & run VisioNext, then enable the extension in **Safari → Settings →
Extensions**. (You may need to allow unsigned extensions via **Develop → Allow
Unsigned Extensions** during development.)

## Files

| File | Role |
|------|------|
| `layout-engine.js` | Measures + decides; writes the layout hooks |
| `enhance.css` | Turns the hooks into the grid (JS-off fallback included) |
| `layout-engine.test.cjs` | Unit tests for the pure decision (`node --test`) |
| `layout-gallery.html` | Thumbnails of mocked screen shares laid out by the real CSS + engine |
| `layout-case.html` | One mocked screen share (`?ar=&n=`); reports its measurements to the gallery |
| `layout-browser.test.cjs` | Runs the gallery in headless Chromium/Chrome and checks each case |
| `call-bridge.js` | Site-independent core: reports the call's mute state; mutes on command |
| `call-bridge.test.cjs` | Unit tests for the core's pure decisions (`node --test`) |
| `providers/*.js` | Per-site adapters (Visio, Google Meet, Teams): read the state, toggle |
| `providers.test.cjs` | Adapter tests against a small fake DOM (`fake-dom.cjs`) |
| `call-bridge.core.test.cjs` | Core state machine tests (reporting, heartbeat, presses) in a `vm` |
| `sites.js` | The call sites (origins, scripts) and their registration, for background + options |
| `background.js` | Call registry + native port to the app; relays mutes to the call tabs |
| `background.test.cjs` | Background tests (port, relay to tabs, registrations) in a `vm` |
| `popup.html` / `popup.js` | Toolbar popup: the layout switch, and a link to the settings |
| `options.html` / `options.js` | Settings: global mute on Google Meet / Teams (one-time opt-in) |
| `options.test.cjs` | Settings page tests (switch states, unavailable sites) in a `vm` |
| `sites.test.cjs` | Checks that manifest, sites.js and providers agree on the sites |
| `manifest.json` | MV3 manifest (Chrome + Firefox + Safari) |
| `icons/` | Extension icons, generated by `make-icons.mjs` (`node make-icons.mjs`) |
| `build-bookmarklet.mjs` | Bundles CSS+JS into `dist/bookmarklet.txt` + `dist/install.html` |
| `package.mjs` | Zips manifest + css + js + icons into `dist/web-extension.zip` |
| `publish-chrome.mjs` | Uploads that zip to the Chrome Web Store and submits it (release workflow) |
