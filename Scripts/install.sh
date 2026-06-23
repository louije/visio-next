#!/usr/bin/env bash
#
# Build visio-next as a real, Developer ID-signed app and install it into
# ~/Applications, so macOS (TCC) treats it as a stable app and remembers the
# Calendar permission across rebuilds — unlike ad-hoc Xcode dev builds.
#
# Usage:  Scripts/install.sh            (build, install, launch)
#         VISIO_NO_OPEN=1 Scripts/install.sh   (build + install, don't launch)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
TEAM="684SSZLSSG"
DEST="$HOME/Applications/VisioNext.app"
BUILD_DIR="$APP_DIR/build/install"

# Resolve a Developer ID Application identity by hash (there can be several certs
# with the same display name; the hash is unambiguous).
IDENTITY="$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application/ {print $2; exit}')"
if [ -z "${IDENTITY:-}" ]; then
  echo "error: no 'Developer ID Application' identity found in your keychain." >&2
  exit 1
fi
echo "Signing identity: $IDENTITY"

command -v xcodegen >/dev/null || { echo "error: install xcodegen (brew install xcodegen)" >&2; exit 1; }

cd "$APP_DIR"
xcodegen generate >/dev/null

echo "Building Release…"
xcodebuild \
  -project VisioNext.xcodeproj \
  -scheme VisioNext \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
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
