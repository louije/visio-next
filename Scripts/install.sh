#!/usr/bin/env bash
#
# Build visio-next and install it into ~/Applications so macOS (TCC) treats it as a
# stable app — and, crucially, signs the app + embedded widget with Apple Development
# (automatic) signing so the App Group is provisioned and the widget can read shared data.
#
# Why automatic (Apple Development) and not Developer ID here: this script is for running
# the app on *your own* Mac. Apple Development signing is stable (same cert → TCC sticks),
# and automatic signing provisions the App Group for both the app and the widget. Developer
# ID + notarization (for distributing to other Macs) is handled separately by the release
# tooling (Stage 4); manual Developer ID signing here would leave the widget's App Group
# unauthorized, so its widget would show no data.
#
# Usage:  Scripts/install.sh            (build, install, launch)
#         VISIO_NO_OPEN=1 Scripts/install.sh   (build + install, don't launch)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
DEST="$HOME/Applications/VisioNext.app"
BUILD_DIR="$APP_DIR/build/install"

command -v xcodegen >/dev/null || { echo "error: install xcodegen (brew install xcodegen)" >&2; exit 1; }

cd "$APP_DIR"
xcodegen generate >/dev/null

echo "Building Release with automatic signing…"
# Signing settings (team, automatic, entitlements) come from project.yml.
# -allowProvisioningUpdates lets Xcode create/refresh the managed profiles (incl. App Group).
xcodebuild \
  -project VisioNext.xcodeproj \
  -scheme VisioNext \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  build >/dev/null

APP_BUILT="$BUILD_DIR/Build/Products/Release/VisioNext.app"
[ -d "$APP_BUILT" ] || { echo "error: build product not found at $APP_BUILT" >&2; exit 1; }

# Quit any running copy, then install into ~/Applications.
pkill -f "VisioNext.app/Contents/MacOS/VisioNext" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP_BUILT" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

codesign --verify --strict "$DEST" && echo "Signature OK"
echo "Installed: $DEST"

if [ -z "${VISIO_NO_OPEN:-}" ]; then
  open "$DEST"
  echo "Launched. Grant Calendar access once on first run."
fi
