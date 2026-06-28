# visio-next

A macOS menu bar app that lists your upcoming calendar meetings (via EventKit) and
one-click-joins their video links. Calendar data comes from the accounts already
configured in macOS Calendar.app — no credentials are stored by this app.

## Layout

- `VisioCore/` — SwiftPM package with all the (tested) domain logic.
- `App/` — the SwiftUI menu bar app. The Xcode project is generated from
  `App/project.yml` with [XcodeGen](https://github.com/yonsm/XcodeGen) and is **not**
  committed.

## Build

```sh
# one-time
brew install xcodegen

# generate the Xcode project
cd App && xcodegen generate

# build from the command line (no signing)
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# run the package tests
cd ../VisioCore && swift test
```

To run the app: `open App/VisioNext.xcodeproj`, set your signing Team under
Signing & Capabilities, then Run. Grant calendar access on first launch.

## Install locally

```sh
Scripts/install.sh   # build, sign (Apple Development), install to ~/Applications, launch
```

Apple Development (automatic) signing is used here so the widget's App Group is
provisioned and TCC (calendar access) sticks across rebuilds.

## Releasing (auto-update via Sparkle)

Releases are Developer ID-signed, notarized, EdDSA-signed for Sparkle, published
as a GitHub Release, and advertised via an appcast on GitHub Pages.

```sh
Scripts/release.sh X.Y.Z
```

The script bumps the version in `project.yml`, archives + exports with automatic
Developer ID provisioning (which also provisions the widget's App Group under
Developer ID), notarizes and staples, then publishes the appcast and zip to the
`gh-pages` branch and creates a GitHub Release. It preflights every prerequisite
below and fails early with a clear message if one is missing.

### One-time prerequisites

- **Developer ID Application** certificate in the login keychain (team `684SSZLSSG`).
- **notarytool keychain profile** named `visio-notary`:
  `xcrun notarytool store-credentials visio-notary`
  (Apple ID + app-specific password, or an App Store Connect API key).
- **Sparkle EdDSA key** in the keychain (public key already in `Info.plist` via
  `project.yml`'s `SUPublicEDKey`, generated once with Sparkle's `generate_keys`).
  The private key never leaves your keychain and is never committed.
- **`gh` CLI** authenticated (`gh auth status`).
- **GitHub Pages** enabled on the `gh-pages` branch (root). It hosts `appcast.xml`
  and every release zip; `SUFeedURL` is `https://louije.github.io/visio-next/appcast.xml`.

## Status

Stages 1–5 implemented: link generator, settings/quit, imminent color, WidgetKit
widget, and Sparkle auto-update. See `docs/superpowers/plans/`.
