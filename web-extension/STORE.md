# Publishing the extension (Chrome Web Store + Firefox AMO)

Both stores accept the **same** `dist/web-extension.zip` (`node package.mjs`). No
signing keys to manage — Google signs the Chrome build, AMO auto-signs the Firefox
build. Safari stays bundled in VisioNext.app; the bookmarklet is the zero-install
fallback.

**Visibility:** publish either **Public** (in the catalogs / searchable) or
**Unlisted** (install + auto-update only via a link you share, e.g. from the
VisioNext site — not in search). Unlisted is the "companion to the app" option.

---

## Chrome Web Store

1. Register once at <https://chrome.google.com/webstore/devconsole> ($5 one-time,
   verify contact info).
2. **New item** → upload `dist/web-extension.zip`.
3. Fill the listing (copy below), set **Visibility = Unlisted** (or Public).
4. **Privacy** tab: single purpose = "Improve Visio calls (adaptive participant layout) and let the companion VisioNext macOS app mute your microphone in every browser call at once"; declare
   **no user data collected**; justify permissions (below). No remote code.
5. Submit. First review is typically hours–days.

Auto-update is automatic once published.

## Firefox (addons.mozilla.org)

1. Free account at <https://addons.mozilla.org/developers/>.
2. **Submit a New Add-on** → upload `dist/web-extension.zip`.
   - **On this site (listed)** → public catalog / one-click install, or
   - **On your own (unlisted)** → AMO signs it, you host the `.xpi` yourself and
     link to it; it auto-updates from your URL.
3. The `browser_specific_settings.gecko.id` is already set, so signing just works.
4. Mostly automated review (minutes–hours).

## Automated publishing

`Scripts/release.sh X.Y.Z` gives the app and the extension the same version and pushes
a `vX.Y.Z` tag. `.github/workflows/publish-extension.yml` then tests the extension
(the layout's browser check runs in Chrome on a macOS runner), packages it, and
submits it to both stores, where it goes through the usual review: listed on Firefox
Add-ons, and to the Chrome Web Store. The listing text and screenshots stay manual.

One-time setup, as repository secrets (`gh secret set NAME`):

- `AMO_API_KEY`, `AMO_API_SECRET` — the JWT issuer and secret from
  <https://addons.mozilla.org/developers/addon/api/key/>.
- `CWS_CLIENT_ID`, `CWS_CLIENT_SECRET`, `CWS_REFRESH_TOKEN` — an OAuth client of a
  Google Cloud project with the Chrome Web Store API enabled, and a refresh token for
  the account that owns the item: follow
  <https://github.com/fregante/chrome-webstore-upload-keys>.
- `CWS_PUBLISHER_ID` — your developer account's id (not the extension's), in the
  Chrome Web Store Developer Dashboard's URL when logged in.

The extension's id (`fnfaiohgodmlfmgoocfiefllaibipimc`) is written in the workflow.
Until the secrets exist the workflow stops and names the missing ones; to publish a
tag again: `gh workflow run publish-extension.yml -f tag=vX.Y.Z`.

---

## Listing copy (paste)

**Name:** VisioNext — adaptive Visio layout

**Summary (≤132):** Adaptive participant layout on Visio, plus a global mute for your browser calls with the VisioNext macOS app.

**Description:**
> On Visio (La Suite numérique, built on LiveKit), when someone shares their screen
> everyone else is squeezed into a single scrolling column. This extension reads
> the shared content's real aspect ratio and lays the participants out
> intelligently: beside the screen or below it, using the grey letterbox bars first,
> in as many lines as it takes to keep everyone in view. It shrinks the shared screen
> only when it must, and when there are too many people to fit, the strip scrolls
> from the first one. Toggle it on or off from the toolbar.
>
> With the companion VisioNext macOS app, its global shortcut also mutes your
> microphone in every open call at once: Visio always, and Google Meet or Teams if
> you allow them in the extension's settings (each site asks for access once).
>
> Unofficial, third-party enhancement. Not affiliated with DINUM, La Suite
> numérique, Google or Microsoft.

**Category:** Productivity · **Language:** English (+ French optional)

## Permission justifications

- **`storage`** — remembers your on/off toggle. Local only.
- **Host access to `visio.numerique.gouv.fr`** — the extension injects a stylesheet
  and a small layout script into the call page to rearrange the participant strip,
  and the mute bridge that reads the microphone state and presses mute. It runs
  elsewhere only on the sites you allow in the extension's settings.
- **`nativeMessaging`** — talks to the companion VisioNext macOS app so its global
  shortcut can mute your microphone in every open call at once. Only each call's mute
  state and a mute command are exchanged, locally; nothing leaves the machine.
- **`scripting`** — runs the mute bridge on Google Meet / Teams only after you allow
  those sites in the extension's settings, including tabs already open, and re-starts the mute
  bridge in open call tabs after an install or update.
- **Optional access to meet.google.com, teams.microsoft.com, teams.cloud.microsoft,
  teams.live.com** — requested only when you turn on « Google Meet » or « Teams » in
  the extension's settings; used to read your microphone's mute state and press mute there.

## Data collection

None. No analytics, no network requests, no accounts. Stored: the on/off preference in
local extension storage. Exchanged locally with the VisioNext app (if installed): each
call tab's (Visio, and Google Meet / Teams if allowed) microphone mute state.

After publishing, add the store-assigned id to `NativeHostInstaller.chromeExtensionIDs`
(`App/Sources/NativeHostInstaller.swift`) so the app's native host accepts it.

## Assets needed

- **Icon** 128×128 — `icons/icon-128.png` (done).
- **Screenshots** — 1280×800 or 640×400. Capture a live call with a screen shared,
  showing the adapted strip (ideally one "side" and one "below" example).
- **Small promo tile** (CWS, optional) 440×280.
