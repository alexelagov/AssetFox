#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ASSETFOX_TEST_BUILD_DIR:-/tmp/AssetFoxParserTests}"
TEST_BINARY="$BUILD_DIR/CollectMediaXMLParserSecurityTests"

mkdir -p "$BUILD_DIR"

# Compile the same file set as the `assetfox-tests` package target: every
# runner file in Tests/ plus the app sources it reaches through the symlinks
# in Tests/Compiled/. Globbing rather than listing keeps this script from
# drifting behind Package.swift again — it once omitted the PixelFormatBitDepth
# pair the @main entry point calls, and stopped compiling (AF-10).
swiftc \
  -swift-version 5 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT_DIR"/Tests/*.swift \
  "$ROOT_DIR"/Tests/Compiled/*.swift \
  -lz \
  -o "$TEST_BINARY"

"$TEST_BINARY"
