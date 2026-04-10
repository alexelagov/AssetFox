#!/bin/bash
# =============================================================
# AssetFox — local package builder for macOS
# Run: bash build.sh
# Output:
#   ~/Desktop/AssetFox.app
#   ~/Desktop/AssetFox-macos.zip
#
# This script does not depend on xcodebuild, which is useful in
# environments where only Command Line Tools are installed.
# =============================================================

set -euo pipefail

APP_NAME="AssetFox"
DISPLAY_NAME="AssetFox"
BUNDLE_ID="com.postprod.assetfox"
MIN_MACOS="15.0"
DESKTOP="$HOME/Desktop"
APP_PATH="$DESKTOP/$APP_NAME.app"
ZIP_PATH="$DESKTOP/${APP_NAME}-macos.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/AssetFox/Sources"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        AssetFox — build .app         ║"
echo "╚══════════════════════════════════════╝"
echo ""

if ! command -v swiftc >/dev/null 2>&1; then
  echo "✗ Swift compiler not found."
  echo "  Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

SWIFT_VER=$(swiftc --version 2>&1 | head -1)
echo "✓ Swift: $SWIFT_VER"
echo "✓ Build strategy: direct swiftc packaging"
if [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ]; then
  echo "⚠ Full Xcode is not installed on this machine."
  echo "  If the SDK/toolchain mismatch appears, run this script on a Mac with Xcode 16+"
  echo "  or set DEVELOPER_DIR to a matching Xcode installation."
fi
echo ""

if [ -d "$APP_PATH" ]; then
  echo "→ Removing previous build..."
  rm -rf "$APP_PATH"
fi

rm -f "$ZIP_PATH"

echo "→ Creating app bundle..."
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Post-production toolkit</string>
</dict>
</plist>
PLIST

echo "✓ Info.plist written"

SOURCE_FILES=()
while IFS= read -r file; do
  SOURCE_FILES+=("$file")
done < <(find "$SRC_DIR" -name '*.swift' -print | sort)

if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
  echo "✗ No Swift sources found under $SRC_DIR"
  exit 1
fi

echo "✓ Found ${#SOURCE_FILES[@]} Swift sources"
echo "→ Compiling universal binary..."

SDK="$(xcrun --show-sdk-path)"
FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework Foundation -framework CryptoKit -framework UniformTypeIdentifiers)

swiftc "${SOURCE_FILES[@]}" -o "$MACOS/${APP_NAME}_arm64" \
  -sdk "$SDK" "${FRAMEWORKS[@]}" -parse-as-library -O \
  -target arm64-apple-macos15.0

swiftc "${SOURCE_FILES[@]}" -o "$MACOS/${APP_NAME}_x86_64" \
  -sdk "$SDK" "${FRAMEWORKS[@]}" -parse-as-library -O \
  -target x86_64-apple-macos15.0

lipo -create -output "$MACOS/$APP_NAME" \
  "$MACOS/${APP_NAME}_arm64" "$MACOS/${APP_NAME}_x86_64"
rm "$MACOS/${APP_NAME}_arm64" "$MACOS/${APP_NAME}_x86_64"

echo "✓ Compilation successful"

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
