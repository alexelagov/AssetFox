#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ASSETFOX_TEST_BUILD_DIR:-/tmp/AssetFoxParserTests}"
TEST_BINARY="$BUILD_DIR/CollectMediaXMLParserSecurityTests"

mkdir -p "$BUILD_DIR"

swiftc \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT_DIR/AssetFox/Sources/CollectMedia/Models/CollectMediaContracts.swift" \
  "$ROOT_DIR/AssetFox/Sources/CollectMedia/Services/CollectMediaXMLParser.swift" \
  "$ROOT_DIR/Tests/CollectMediaXMLParserSecurityTests.swift" \
  -lz \
  -o "$TEST_BINARY"

"$TEST_BINARY"
