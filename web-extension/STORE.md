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
4. **Privacy** tab: single purpose = "adapt the video layout on Visio"; declare
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

---

## Listing copy (paste)

**Name:** VisioNext — adaptive Visio layout

**Summary (≤132):** Adapts the participant strip to the shared screen on Visio
(visio.numerique.gouv.fr) — more faces, placed where the grey bars are.

**Description:**
> On Visio (La Suite numérique, built on LiveKit), when someone shares their screen
> everyone else is squeezed into a single scrolling column. This extension reads
> the shared content's real aspect ratio and lays the participants out
> intelligently: beside the screen or below it — wherever the grey letterbox bars
> leave room — in one or two lines, so you can see more faces at once. Toggle it on
> or off from the toolbar.
>
> Unofficial, third-party enhancement. Not affiliated with DINUM, La Suite
> numérique, or Google.

**Category:** Productivity · **Language:** English (+ French optional)

## Permission justifications

- **`storage`** — remembers your on/off toggle. Local only.
- **Host access to `visio.numerique.gouv.fr`** — the extension injects a stylesheet
  and a small layout script into the call page to rearrange the participant strip.
  It runs nowhere else.
- **`nativeMessaging`** — talks to the companion VisioNext macOS app so its global
  shortcut can mute your microphone in every open call at once. Only each call's mute
  state and a mute command are exchanged, locally; nothing leaves the machine.
- **`scripting`** — runs the mute bridge on Google Meet / Teams only after you allow
  those sites from the popup, including tabs already open.
- **Optional access to meet.google.com, teams.microsoft.com, teams.cloud.microsoft,
  teams.live.com** — requested only when you turn on « Google Meet » or « Teams » in
  the popup; used to read your microphone's mute state and press mute there.

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
