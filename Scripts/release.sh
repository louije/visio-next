#!/usr/bin/env bash
#
# Build, Developer ID-sign, notarize, and publish a VisioNext release in one command.
#
# Usage:  Scripts/release.sh X.Y.Z
#
# What it does:
#   1. Preflight: xcodegen, gh auth, Developer ID cert, notarytool profile, generate_appcast.
#   2. Bump MARKETING_VERSION (=X.Y.Z) and CURRENT_PROJECT_VERSION (+1) in project.yml.
#   3. xcodebuild archive + -exportArchive with automatic Developer ID provisioning
#      (-allowProvisioningUpdates also provisions the widget's App Group under Developer ID).
#   4. Notarize (notarytool --wait) and staple the .app.
#   5. Zip the stapled .app.
#   6. Update the appcast on the gh-pages branch (hosts appcast.xml + all zips) and push.
#   7. Tag main, push, and create a GitHub Release with the zip attached.
#
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: Scripts/release.sh X.Y.Z" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
TEAM_ID="684SSZLSSG"
REPO="louije/visio-next"
PAGES_URL="https://louije.github.io/visio-next"
NOTARY_PROFILE="visio-notary"
BUILD_DIR="$APP_DIR/build/release"
ARCHIVE="$BUILD_DIR/VisioNext.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
ZIP_NAME="VisioNext-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
PAGES_WT="$ROOT/build/gh-pages"

# --- Preflight -------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }
command -v gh >/dev/null || { echo "error: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated (gh auth login)" >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "error: no Developer ID Application certificate in keychain" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || { echo "error: notarytool profile '$NOTARY_PROFILE' missing. Run: xcrun notarytool store-credentials $NOTARY_PROFILE" >&2; exit 1; }

# --- Bump version in project.yml ------------------------------------------
cd "$APP_DIR"
CURRENT_BUILD="$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/[^0-9]//g')"
NEXT_BUILD="$((CURRENT_BUILD + 1))"
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
xcodegen generate >/dev/null
echo "Version $VERSION (build $NEXT_BUILD)"

# --- Locate Sparkle's generate_appcast (resolved by the build below) -------
find_gen() { find ~/Library/Developer/Xcode/DerivedData "$APP_DIR/build" \
  -path '*/artifacts/*' -name generate_appcast -type f 2>/dev/null | head -1; }

# --- Archive + export (Developer ID, automatic provisioning) ---------------
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
echo "Archiving…"
xcodebuild archive \
  -project VisioNext.xcodeproj -scheme VisioNext \
  -configuration Release -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates >/dev/null

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
PLIST

echo "Exporting…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates >/dev/null

APP="$EXPORT_DIR/VisioNext.app"
[ -d "$APP" ] || { echo "error: exported app not found at $APP" >&2; exit 1; }

# --- Notarize + staple -----------------------------------------------------
echo "Notarizing (this can take a few minutes)…"
NOTARY_ZIP="$BUILD_DIR/notarize.zip"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- Zip the stapled app for distribution ----------------------------------
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

# --- Update the appcast on gh-pages (hosts appcast.xml + every zip) ---------
GEN="$(find_gen)"
[ -n "$GEN" ] || { echo "error: generate_appcast not found (open the project in Xcode once to resolve Sparkle)" >&2; exit 1; }

rm -rf "$PAGES_WT"
git -C "$ROOT" worktree remove --force "$PAGES_WT" 2>/dev/null || true
git -C "$ROOT" fetch origin gh-pages >/dev/null 2>&1 || true
git -C "$ROOT" worktree add "$PAGES_WT" gh-pages
cp "$ZIP_PATH" "$PAGES_WT/"
"$GEN" "$PAGES_WT" --download-url-prefix "$PAGES_URL/"
git -C "$PAGES_WT" add -A
git -C "$PAGES_WT" commit -m "Release $VERSION"
git -C "$PAGES_WT" push origin gh-pages
git -C "$ROOT" worktree remove --force "$PAGES_WT"

# --- Tag main + GitHub Release (human-facing, attaches the zip) -------------
git -C "$ROOT" add App/project.yml App/Info.plist
git -C "$ROOT" commit -m "Release $VERSION"
git -C "$ROOT" tag "v$VERSION"
git -C "$ROOT" push origin main "v$VERSION"
gh release create "v$VERSION" "$ZIP_PATH" --repo "$REPO" --title "v$VERSION" --generate-notes

echo "Released $VERSION → $PAGES_URL/appcast.xml"
