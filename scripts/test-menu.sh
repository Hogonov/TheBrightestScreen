#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
sources=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/main.swift" ]]; then sources+=("$source"); fi
done
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/module-cache" \
  -framework AppKit -framework MetalKit -framework CoreGraphics \
  "${sources[@]}" Tests/MenuTests.swift -o build/menu-tests
# Requires a logged-in macOS GUI session. Opens and dismisses one menu;
# does not enable XDR or change native brightness.
build/menu-tests
