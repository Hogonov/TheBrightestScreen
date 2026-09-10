#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/build/module-cache" \
  Sources/BrightnessPolicy.swift Sources/GammaTable.swift Tests/PolicyTests.swift -o build/policy-tests
build/policy-tests
