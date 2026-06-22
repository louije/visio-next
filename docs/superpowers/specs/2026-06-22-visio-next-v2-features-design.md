# visio-next v2 features — design

**Date:** 2026-06-22
**Status:** Approved (pending spec review)

## Summary

Five staged, largely independent features on top of the shipped Phase 1 menu bar app:
a configurable "create a new visio link" generator, a settings reorganization with
Quit relocation, tunable imminent-icon color, Sparkle auto-update, and a WidgetKit
widget. Each stage is independently shippable and gets its own implementation plan
and review pass.

## Locked decisions

- **Menu bar stays `MenuBarExtra`.** The right-click context menu from the original
  ask is dropped (SwiftUI `MenuBarExtra` can't offer a distinct right-click menu).
  Consequence: Quit moves to Settings → Général only; the popover footer becomes
  `[Réglages…] [Créer un lien]` (Quitter removed).
- **Developer ID signing + notarization** is available → full, warning-free Sparkle.
- **Link template:** editable base URL + 3 fixed blocks (lengths 3/4/3), each
  literal-or-random; random charset is `[a-z0-9]`.
- **Widgets:** two small (New call · Next call[s]) + one medium (combined),
  interactive via App Intents.

## Build order

1 → 2 (uses the template config) → 3 (trivial) → 4 → 5 (largest).

---

## Stage 1 — "Créer un lien" generator

### Core (VisioCore)
- `LinkBlock { length: Int; value: String }` — `value` empty ⇒ random.
- `LinkTemplate { baseURL: String; blocks: [LinkBlock] }`.
  Default: `baseURL = "https://visio.numerique.gouv.fr/"`,
  `blocks = [LinkBlock(3, ""), LinkBlock(4, ""), LinkBlock(3, "")]` — all blocks blank
  (fully random) for new users. (The maintainer fills in their own `pdi` / `ljt` via
  Settings.)
- `LinkGenerator.generate(from: LinkTemplate, using: inout RandomNumberGenerator)`
  → for each block, its `value` if non-empty, else a random `[a-z0-9]` string of
  `length`; blocks joined with `-`; result prefixed by `baseURL`. The injected RNG
  lets tests assert format, lengths, and literal preservation deterministically.
- Add `linkTemplate: LinkTemplate` to `Settings` (Codable; default as above).

### App
- Popover footer becomes `[Réglages…] [Créer un lien]`.
- Tapping **Créer un lien** generates a link, writes it to `NSPasteboard.general`,
  and does **not** dismiss the popover (`MenuBarExtra(.window)` keeps it open).
- A transient confirmation — **"Nouveau lien copié"** (readable, not shorthand) —
  appears next to the button for ~2 s, then clears (a cancelable `Task`).

### Testing
`LinkGenerator` with a seeded RNG: literal blocks preserved, random blocks have the
right length and charset, separators/baseURL correct. `Settings` round-trip includes
`linkTemplate`.

---

## Stage 2 — Settings reorganization + Quit

- Tab order becomes **Général** (first), **Calendriers**, **Services visio**.
- **Général** contains, top to bottom:
  - "Ouvrir les liens dans" browser picker (moved from the old tab).
  - **Comb config** for the generator: a base-URL field plus three short monospaced
    block fields (max lengths 3/4/3, placeholder "aléatoire" when empty).
  - A **Quitter** button pinned at the bottom.
- **Remove `allowAnyURLFallback` entirely** — from `Settings`, `LinkExtractor`
  (drop the fallback parameter/branch), `EventKitCalendarService`, the view model,
  and the related tests.

### Testing
`LinkExtractor` tests updated to drop the fallback cases. `Settings` round-trip
reflects the removed field and the new `linkTemplate`.

---

## Stage 3 — Imminent icon color

Extract the imminent tint into a single `MenuBarIcon.imminentColor` constant with
3–4 commented candidates (e.g. `.systemRed`, `.systemOrange`, `.controlAccentColor`,
`.systemPink`) so the user can swap one line and eyeball the result in Xcode. No other
behavior change.

---

## Stage 4 — Sparkle auto-update

### App integration
- Sparkle added via SPM (in `App/project.yml` packages).
- EdDSA key pair: public key in Info.plist (`SUPublicEDKey`), private key in the
  user's keychain (never committed).
- Info.plist: `SUFeedURL` → the GitHub Pages appcast URL, `SUEnableAutomaticChecks`.
- A `SPUStandardUpdaterController` wired into the app; a "Rechercher les mises à
  jour…" item in Général triggers `checkForUpdates`.

### Release tooling — `Scripts/release.sh` (one command)
1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
2. `xcodebuild archive` → export with Developer ID.
3. Notarize with `xcrun notarytool` (using a stored keychain profile) + `stapler`.
4. Zip the `.app`.
5. Sparkle `generate_appcast` — EdDSA-signs the zip and updates `appcast.xml`.
6. `gh release create` — upload the zip as a release asset.
7. Publish `appcast.xml` to GitHub Pages (commit under `docs/` or `gh-pages`).

### Prerequisites (documented in README)
Developer ID Application cert in keychain; a `notarytool` keychain profile
(app-specific password or App Store Connect API key); `gh` authenticated; Sparkle
EdDSA private key present. The script checks for these and fails early with a clear
message if any is missing.

### Hosting
Binaries: GitHub Release assets. Appcast: `appcast.xml` served from GitHub Pages.

---

## Stage 5 — Widget

### Shared data
- Enable the **real App Group** (`group.com.meidosem.visionext`) on both the app and
  the widget (entitlements via XcodeGen).
- On every refresh, the app writes a small render **snapshot** (the upcoming call[s]
  plus the current `linkTemplate`) to the App Group store, so the widget renders
  without querying EventKit itself.

### Widget configs (one extension target)
- **Small — "Nouveau lien":** a button running `NewCallIntent` (generate + copy a
  link from the shared template).
- **Small — "Prochain appel":** the next upcoming call, plus any others starting
  within a **10-minute span** of it; each with a Rejoindre control (`JoinCallIntent`).
- **Medium:** the two combined (next call[s] + a new-call button).

### App Intents
- `NewCallIntent` — generates a link via `LinkGenerator` + the shared template, copies
  it to the pasteboard, returns a confirmation; refreshes the timeline.
- `JoinCallIntent(url:)` — opens the call URL.

### Scope note
The widget's "next call(s)" looks at upcoming calls over the next ~24 h (grouped by a
10-minute span), which is intentionally broader than the menu popover's ±30-minute
"join now" window.

### Testing
The 10-minute grouping and "next call(s)" selection are pure functions in VisioCore,
unit-tested. Intents and timeline provider are integration-verified by building and
running.

---

## Out of scope

- Right-click menu bar context menu (dropped per the MenuBarExtra decision).
- Any change to calendar selection or link-extraction matching beyond removing the
  fallback option.
