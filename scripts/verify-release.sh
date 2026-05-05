#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TrellisMac"
BUNDLE_ID="io.github.trellis-mac.TrellisMac"
MIN_MACOS="13.0"
PLIST_FILE="$ROOT_DIR/mac-app/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_FILE")"
DMG_NAME="$APP_NAME-$VERSION-arm64.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
MOUNT_DIR=""
REQUIRE_GATEKEEPER="${REQUIRE_GATEKEEPER:-0}"

cleanup() {
    local status=$?

    if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        local mount_dir_real
        mount_dir_real="$(cd "$MOUNT_DIR" 2>/dev/null && pwd -P)"
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || status=1

        for _ in 1 2 3 4 5; do
            if ! mount | grep -Fq " on $MOUNT_DIR " && ! mount | grep -Fq " on $mount_dir_real "; then
                break
            fi
            sleep 1
        done

        if mount | grep -Fq " on $MOUNT_DIR " || mount | grep -Fq " on $mount_dir_real "; then
            echo "error: failed to detach mounted DMG at $MOUNT_DIR" >&2
            status=1
        fi

        rmdir "$MOUNT_DIR" 2>/dev/null || status=1
    fi

    exit "$status"
}
trap cleanup EXIT

verify_app_bundle() {
    local app_dir="$1"
    local contents_dir="$app_dir/Contents"
    local app_plist="$contents_dir/Info.plist"
    local executable_path="$contents_dir/MacOS/$APP_NAME"
    local resources_dir="$contents_dir/Resources"
    local app_bundle_id
    local app_min_macos
    local app_version

    test -d "$app_dir"
    test -d "$contents_dir"
    test -x "$executable_path"
    test -f "$app_plist"
    test -d "$resources_dir"
    test -f "$resources_dir/README-FIRST.txt"
    test -f "$resources_dir/TrellisMac.icns"
    plutil -lint "$app_plist"

    app_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_plist")"
    if [ "$app_bundle_id" != "$BUNDLE_ID" ]; then
        echo "error: bundle identifier is $app_bundle_id; expected $BUNDLE_ID" >&2
        exit 1
    fi

    app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_plist")"
    if [ "$app_version" != "$VERSION" ]; then
        echo "error: app version is $app_version; expected $VERSION" >&2
        exit 1
    fi

    app_min_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_plist")"
    if [ "$app_min_macos" != "$MIN_MACOS" ]; then
        echo "error: minimum macOS is $app_min_macos; expected $MIN_MACOS" >&2
        exit 1
    fi

    if ! lipo -archs "$executable_path" | grep -qw arm64; then
        echo "error: app executable is not arm64: $executable_path" >&2
        exit 1
    fi

    codesign --verify --strict --verbose=2 "$app_dir"
}

verify_gatekeeper() {
    if [ "$REQUIRE_GATEKEEPER" != "1" ]; then
        echo "Gatekeeper assessment skipped (set REQUIRE_GATEKEEPER=1 for signed/notarized release checks)."
        return
    fi

    echo "== Verifying Gatekeeper assessment =="
    spctl -a -vv -t exec "$APP_DIR"
    spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
}

echo "== Verifying plist =="
plutil -lint "$PLIST_FILE"

echo "== Verifying app bundle =="
verify_app_bundle "$APP_DIR"

echo "== Verifying DMG =="
test -f "$DMG_PATH"
test -f "$DMG_PATH.sha256"

SHA_ENTRY_NAME="$(awk 'NF >= 2 { print $2; exit }' "$DMG_PATH.sha256")"
if [ "$SHA_ENTRY_NAME" != "$DMG_NAME" ]; then
    echo "error: checksum file targets $SHA_ENTRY_NAME; expected $DMG_NAME" >&2
    exit 1
fi

EXPECTED_SHA="$(awk 'NF >= 2 { print $1; exit }' "$DMG_PATH.sha256")"
ACTUAL_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "error: checksum mismatch for $DMG_NAME" >&2
    exit 1
fi

(cd "$DIST_DIR" && shasum -a 256 -c "$DMG_NAME.sha256")

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
test -d "$MOUNT_DIR/$APP_NAME.app"
test -L "$MOUNT_DIR/Applications"
test -f "$MOUNT_DIR/README-FIRST.txt"
verify_app_bundle "$MOUNT_DIR/$APP_NAME.app"
verify_gatekeeper

echo "Release verification passed for $APP_NAME $VERSION"
