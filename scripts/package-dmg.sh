#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TrellisMac"
PLIST_FILE="$ROOT_DIR/mac-app/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_FILE")"
DMG_NAME="$APP_NAME-$VERSION-arm64.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_PLIST="$APP_DIR/Contents/Info.plist"
TMP_DMG="$DIST_DIR/$APP_NAME-$VERSION-arm64.tmp.dmg"
TMP_SHA="$DMG_PATH.sha256.tmp"

cleanup() {
    rm -rf "$STAGING_DIR" "$TMP_DMG" "$TMP_SHA"
}
trap cleanup EXIT

if [ ! -d "$APP_DIR" ]; then
    echo "error: missing $APP_DIR; run ./build-mac-app.sh first" >&2
    exit 1
fi

if [ ! -f "$APP_PLIST" ]; then
    echo "error: missing bundled plist: $APP_PLIST; run ./build-mac-app.sh first" >&2
    exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "error: stale app bundle version $APP_VERSION; expected $VERSION. Run ./build-mac-app.sh first" >&2
    exit 1
fi

rm -rf "$STAGING_DIR" "$TMP_DMG" "$TMP_SHA"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/README-FIRST.txt" <<'README'
Drag TrellisMac.app to Applications, or run it directly from this disk image.

TrellisMac requires a local trellis-mac repository checkout for setup.sh, generate.py,
the Python virtual environment, and Hugging Face model weights.
README

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$TMP_DMG"

mv "$TMP_DMG" "$DMG_PATH"
(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256.tmp"
    mv "$DMG_NAME.sha256.tmp" "$DMG_NAME.sha256"
)

echo "DMG created:"
echo "  $DMG_PATH"
echo "Checksum:"
cat "$DMG_PATH.sha256"
