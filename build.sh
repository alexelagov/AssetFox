#!/bin/bash
# =============================================================
# AssetFox — local package builder for macOS
# Run: bash build.sh
# Output:
#   ~/Desktop/AssetFox.app
#   ~/Desktop/AssetFox-macos.zip
#
# Builds through AssetFox.xcodeproj, so it needs full Xcode 16+
# (found automatically in /Applications even when xcode-select
# points at Command Line Tools).
# =============================================================

set -euo pipefail

APP_NAME="AssetFox"
DESKTOP="$HOME/Desktop"
APP_PATH="$DESKTOP/$APP_NAME.app"
ZIP_PATH="$DESKTOP/${APP_NAME}-macos.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        AssetFox — build .app         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# The app target needs things a bare swiftc call never had: the
# MediaInfoLib bridge (an Objective-C++ file behind a bridging header), the
# embedded libmediainfo.dylib with its install name rewritten, and the
# SwiftUI macro plugins (@State and friends) that ship only with full Xcode.
# The Xcode project already does all three, so this script builds through it
# rather than keeping a second, drifting copy of the recipe. It used to: the
# swiftc version stopped compiling the day the MediaInfoLib bridge landed.
if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app ]; then
    # xcode-select points at Command Line Tools, but Xcode is installed.
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "✗ Full Xcode not found."
    echo "  AssetFox's SwiftUI macros and MediaInfoLib bridge need Xcode 16+;"
    echo "  Command Line Tools alone cannot build the app."
    exit 1
  fi
fi

XCODE_VER=$(xcodebuild -version 2>&1 | head -1)
echo "✓ $XCODE_VER"
echo "✓ Build strategy: xcodebuild (AssetFox.xcodeproj, Release, universal)"
echo ""

echo "→ Running parser security tests..."
bash "$SCRIPT_DIR/script/test_collect_media_xml_parser.sh"
echo "✓ Tests passed"
echo ""

DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/assetfox-build.XXXXXX")"
trap 'rm -rf "$DERIVED_DATA"' EXIT

echo "→ Compiling universal binary..."
xcodebuild \
  -project "$SCRIPT_DIR/AssetFox.xcodeproj" \
  -scheme AssetFox \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build
echo "✓ Compilation successful"

if [ -d "$APP_PATH" ]; then
  echo "→ Removing previous build..."
  rm -rf "$APP_PATH"
fi
rm -f "$ZIP_PATH"

ditto "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app" "$APP_PATH"
echo "✓ App bundle copied to $APP_PATH"

echo "→ Applying ad-hoc signature..."
if codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1; then
  echo "✓ Ad-hoc signed"
else
  echo "  (codesign skipped or failed; the app can still be opened locally)"
fi

echo "→ Creating transfer zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -sh "$APP_PATH" | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✓  BUILD COMPLETE                  ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  App bundle: $APP_PATH"
echo "  Zip archive: $ZIP_PATH"
echo "  Size: $SIZE"
echo ""
echo "  On another Mac:"
echo "  1. Copy the .zip or .app"
echo "  2. Unzip if needed"
echo "  3. If Gatekeeper blocks first launch, use Open Anyway"
echo ""
