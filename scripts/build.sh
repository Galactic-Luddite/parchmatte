#!/usr/bin/env bash
# Build Parchmatte.app from source with SwiftPM and zip it.
#
# Usage:  scripts/build.sh
# Output: dist/Parchmatte.app and dist/Parchmatte-<version>-macOS.zip
#
# The result is ad-hoc signed, which is all a Mac needs to run an app you
# built yourself. See the README for opening it the first time.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Parchmatte"
BUNDLE_INFO="Sources/$APP_NAME/AppBundleInfo.xml"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE_INFO")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BUNDLE_INFO" "$APP_BUNDLE/Contents/Info.plist"
cp -R "Sources/$APP_NAME/Textures" "$APP_BUNDLE/Contents/Resources/Textures"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing (App Sandbox + hardened runtime, same as the store build)"
codesign --force --sign - --options runtime \
    --entitlements "Resources/$APP_NAME-Free.entitlements" "$APP_BUNDLE"

echo "==> Zipping"
(cd "$DIST_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION-macOS.zip")

echo "==> Done: $APP_BUNDLE"
