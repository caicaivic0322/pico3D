#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TrellisMac"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_FILE="$ROOT_DIR/mac-app/TrellisMacApp.swift"
PLIST_FILE="$ROOT_DIR/mac-app/Info.plist"
RESOURCE_SOURCE_DIR="$ROOT_DIR/mac-app/Resources"
EXECUTABLE_PATH="$MACOS_DIR/$APP_NAME"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
TEMP_BACKEND_DIR=""

cleanup() {
    if [ -n "$TEMP_BACKEND_DIR" ] && [ -d "$TEMP_BACKEND_DIR" ]; then
        rm -rf "$TEMP_BACKEND_DIR"
    fi
}
trap cleanup EXIT

validate_resources() {
    local resource_dir="$1"
    local exclude_backend="${2:-0}"
    local find_cmd=(find "$resource_dir")

    if [ "$exclude_backend" = "1" ]; then
        find_cmd+=(
            "("
            -path "$resource_dir/Backend"
            -o
            -path "$resource_dir/Backend/*"
            ")"
            -prune
            -o
        )
    fi

    if [ -d "$resource_dir" ]; then
        if "${find_cmd[@]}" \
            \( \
                -type l -o \
                \( -type d \( -name "*.app" -o -name "*.framework" \) \) -o \
                \( -type f \( -perm -111 -o -name "*.dylib" \) \) \
            \) \
            -print -quit | grep -q .
        then
            echo "error: resources must not contain symlinks, app/framework bundles, or executable code" >&2
            exit 1
        fi
    fi
}

echo "== Building $APP_NAME =="

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: swiftc not found. Install Xcode or Command Line Tools first." >&2
    exit 1
fi

if [ ! -f "$SOURCE_FILE" ]; then
    echo "error: missing Swift source: $SOURCE_FILE" >&2
    exit 1
fi

if [ ! -f "$PLIST_FILE" ]; then
    echo "error: missing plist: $PLIST_FILE" >&2
    exit 1
fi

validate_resources "$RESOURCE_SOURCE_DIR" 1
TEMP_BACKEND_DIR="$(mktemp -d "$ROOT_DIR/.backend-stage.XXXXXX")"
"$ROOT_DIR/scripts/stage-backend-resources.sh" "$TEMP_BACKEND_DIR"
validate_resources "$TEMP_BACKEND_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -sdk "$SDKROOT" \
    -parse-as-library \
    -framework AppKit \
    -framework SceneKit \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    "$SOURCE_FILE" \
    -o "$EXECUTABLE_PATH"

cp "$PLIST_FILE" "$CONTENTS_DIR/Info.plist"

if [ -d "$RESOURCE_SOURCE_DIR" ]; then
    rsync -a --exclude "Backend/" "$RESOURCE_SOURCE_DIR"/ "$RESOURCES_DIR"/
fi
rsync -a "$TEMP_BACKEND_DIR"/ "$RESOURCES_DIR/Backend"/

chmod +x "$EXECUTABLE_PATH"
lipo -archs "$EXECUTABLE_PATH" | grep -qw arm64

if command -v codesign >/dev/null 2>&1; then
    echo "Signing app with identity: $SIGN_IDENTITY"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
    codesign --verify --strict --verbose=2 "$APP_DIR"
fi

echo
echo "App built successfully:"
echo "  $APP_DIR"
echo
echo "Open it with:"
echo "  open \"$APP_DIR\""
