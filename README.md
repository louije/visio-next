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

## Status

Phase 1 (menu bar app) — implemented. Phase 2 (WidgetKit widget reading a shared
App Group snapshot) — planned, see `docs/superpowers/plans/`.
