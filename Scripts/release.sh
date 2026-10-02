#!/usr/bin/env bash
#
# Build, Developer ID-sign, notarize, and publish a VisioNext release in one command.
#
# Usage:  Scripts/release.sh X.Y.Z
#
# What it does:
#   1. Preflight: xcodegen, gh auth, Developer ID cert, create-dmg, notarytool profile.
#   2. Bump MARKETING_VERSION (=X.Y.Z) and CURRENT_PROJECT_VERSION (+1) in project.yml.
#   3. xcodebuild archive + -exportArchive with automatic Developer ID provisioning
#      (-allowProvisioningUpdates also provisions the widget's App Group under Developer ID).
#   4. Notarize (notarytool --wait) and staple the .app.
#   5. Zip the stapled .app (for Sparkle updates) and build a signed + notarized DMG
#      (the human download — robust against unzip tools that strip the ticket).
#   6. Tag main, push, and create a GitHub Release with the DMG + zip attached.
#   7. Regenerate the appcast (no deltas) on gh-pages with enclosure URLs pointing at the
#      GitHub Release assets so Sparkle downloads are counted, then push gh-pages.
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
# Versionless on purpose: a stable asset name makes
# github.com/…/releases/latest/download/VisioNext.dmg always resolve to the newest.
DMG_PATH="$BUILD_DIR/VisioNext.dmg"
PAGES_WT="$ROOT/build/gh-pages"

# --- Preflight -------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }
command -v gh >/dev/null || { echo "error: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated (gh auth login)" >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "error: no Developer ID Application certificate in keychain" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "error: npm install --global create-dmg" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || { echo "error: notarytool profile '$NOTARY_PROFILE' missing. Run: xcrun notarytool store-credentials $NOTARY_PROFILE" >&2; exit 1; }

# This keychain has several identically-named "Developer ID Application" certs, so
# create-dmg's name-based lookup is ambiguous; resolve an explicit SHA-1 for it.
SIGN_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')"

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

# The app, the widget and the Safari extension share data and the bridge socket only
# through the App Group, which a Developer ID build gets only from its provisioning
# profiles: without them a bundle ships signed but silently cut off from the others.
APP_GROUP="group.com.meidosem.visionext"
BUNDLES=("$APP")
for APPEX in "$APP"/Contents/PlugIns/*.appex; do
  if [ -d "$APPEX" ]; then BUNDLES+=("$APPEX"); fi   # the glob stays literal when nothing matches
done
[ "${#BUNDLES[@]}" -gt 1 ] || { echo "error: no app extensions in $APP/Contents/PlugIns" >&2; exit 1; }
for BUNDLE in "${BUNDLES[@]}"; do
  ENTITLEMENTS="$(codesign -d --entitlements - "$BUNDLE" 2>/dev/null)" \
    || { echo "error: can't read the entitlements of $BUNDLE" >&2; exit 1; }
  [[ "$ENTITLEMENTS" == *"$APP_GROUP"* ]] \
    || { echo "error: $BUNDLE not signed with the $APP_GROUP App Group" >&2; exit 1; }
  [ -f "$BUNDLE/Contents/embedded.provisionprofile" ] \
    || { echo "error: no embedded.provisionprofile in $BUNDLE" >&2; exit 1; }
done

# --- Notarize + staple -----------------------------------------------------
echo "Notarizing (this can take a few minutes)…"
NOTARY_ZIP="$BUILD_DIR/notarize.zip"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- Zip the stapled app (Sparkle updates keep using this) ------------------
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

# --- Styled DMG for the human download -------------------------------------
# A DMG survives download/unarchive far better than a bare zip (no third-party
# unzipper strips the notarization ticket). create-dmg signs it (explicit
# SIGN_ID) but does NOT notarize, so notarize + staple it here — the app inside
# is already stapled, so both layers carry the ticket.
echo "Building DMG…"
rm -f "$DMG_PATH"
create-dmg "$APP" "$BUILD_DIR" --overwrite --no-version-in-filename --identity="$SIGN_ID"
[ -f "$DMG_PATH" ] || { echo "error: DMG not created at $DMG_PATH" >&2; exit 1; }
codesign --verify --strict "$DMG_PATH" || { echo "error: DMG not code-signed" >&2; exit 1; }
echo "Notarizing DMG…"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# Forget the build products so this Mac keeps using the installed copy's Safari
# extension: Safari lists the extension of every VisioNext.app LaunchServices knows,
# and the app's SFSafariApplication.dispatchMessage only reaches the copy bundled with it.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -u "$ARCHIVE/Products/Applications/VisioNext.app" 2>/dev/null || true

# --- Tag main + GitHub Release (hosts the zip; this is the download target) -
# Must precede the appcast push so the release asset exists when clients fetch
# the new appcast and resolve its enclosure URLs.
git -C "$ROOT" add App/project.yml App/Info.plist
git -C "$ROOT" commit -m "Release $VERSION"
git -C "$ROOT" tag "v$VERSION"
git -C "$ROOT" push origin main "v$VERSION"
gh release create "v$VERSION" "$DMG_PATH" "$ZIP_PATH" --repo "$REPO" --title "v$VERSION" --generate-notes

# --- Regenerate the appcast on gh-pages, pointing enclosures at the Releases -
# gh-pages still hosts appcast.xml (SUFeedURL) and keeps the zips as the corpus
# generate_appcast needs to rebuild the full feed. Deltas are disabled, and every
# enclosure URL is rewritten from the Pages host to the per-version Release asset
# so Sparkle update downloads register on each release's download_count.
GEN="$(find_gen)"
[ -n "$GEN" ] || { echo "error: generate_appcast not found (open the project in Xcode once to resolve Sparkle)" >&2; exit 1; }

rm -rf "$PAGES_WT"
git -C "$ROOT" worktree remove --force "$PAGES_WT" 2>/dev/null || true
git -C "$ROOT" fetch origin gh-pages >/dev/null 2>&1 || true
git -C "$ROOT" worktree add "$PAGES_WT" gh-pages
cp "$ZIP_PATH" "$PAGES_WT/"
rm -f "$PAGES_WT"/*.delta
"$GEN" "$PAGES_WT" --maximum-deltas 0 --download-url-prefix "$PAGES_URL/"
# Rewrite enclosure URLs: Pages host -> per-version GitHub Release asset.
sed -i '' -E \
  "s#$PAGES_URL/VisioNext-([0-9]+\.[0-9]+\.[0-9]+)\.zip#https://github.com/$REPO/releases/download/v\1/VisioNext-\1.zip#g" \
  "$PAGES_WT/appcast.xml"
git -C "$PAGES_WT" add -A
git -C "$PAGES_WT" commit -m "Release $VERSION"
git -C "$PAGES_WT" push origin gh-pages
git -C "$ROOT" worktree remove --force "$PAGES_WT"

echo "Released $VERSION → $PAGES_URL/appcast.xml (enclosures → GitHub Releases)"
