#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/Brighter.app"
case "${1:-}" in
  "") ;;
  --test) APP_DIR="$BUILD_DIR/BrighterDiagnostics.app" ;;
  *) echo "Usage: bash scripts/build.sh [--test]" >&2; exit 64 ;;
esac
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -sdk "$SDK_DIR" -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -framework AppKit -framework MetalKit -framework CoreGraphics \
  Sources/*.swift -o "$APP_DIR/Contents/MacOS/Brighter"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ "${1:-}" == "--test" ]]; then
  plutil -replace CFBundleIdentifier -string local.alexandr.Brighter.Diagnostics "$APP_DIR/Contents/Info.plist"
  plutil -replace CFBundleName -string 'Brighter Diagnostics' "$APP_DIR/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string 'Brighter Diagnostics' "$APP_DIR/Contents/Info.plist"
fi
cp LICENSE THIRD_PARTY_NOTICES.md README.md "$APP_DIR/Contents/Resources/"
xcrun swiftc -swift-version 5 -sdk "$SDK_DIR" -module-cache-path "$BUILD_DIR/module-cache" \
  scripts/Icon.swift -o "$BUILD_DIR/create-icon"
"$BUILD_DIR/create-icon" "$BUILD_DIR/Brighter.iconset"
iconutil -c icns "$BUILD_DIR/Brighter.iconset" -o "$APP_DIR/Contents/Resources/Brighter.icns"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
echo "Built: $APP_DIR"
