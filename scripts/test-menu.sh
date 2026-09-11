#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
TEST_APP="$PROJECT_DIR/build/BrighterMenuTests.app"
mkdir -p "$TEST_APP/Contents/MacOS"
cp Resources/Info.plist "$TEST_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.alexandr.Brighter.MenuTests "$TEST_APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string menu-tests "$TEST_APP/Contents/Info.plist"
plutil -replace CFBundleName -string 'Brighter Menu Tests' "$TEST_APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string 'Brighter Menu Tests' "$TEST_APP/Contents/Info.plist"
plutil -remove CFBundleIconFile "$TEST_APP/Contents/Info.plist"
sources=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/main.swift" ]]; then sources+=("$source"); fi
done
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/module-cache" \
  -framework AppKit -framework MetalKit -framework CoreGraphics \
  "${sources[@]}" Tests/MenuTests.swift -o "$TEST_APP/Contents/MacOS/menu-tests"
codesign --force --sign - "$TEST_APP"
# Requires a logged-in macOS GUI session. Opens and dismisses one menu;
# does not enable XDR or change native brightness.
"$TEST_APP/Contents/MacOS/menu-tests"
