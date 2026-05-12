#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${ASSETFOX_DERIVED_DATA_PATH:-/tmp/AssetFoxReleaseDerivedData}"
LOCAL_TELEMETRY_CONFIG="$ROOT_DIR/Config/Telemetry.local.xcconfig"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="AssetFox"
APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
APP_DEST="$DIST_DIR/$APP_NAME.app"
ZIP_DEST="$DIST_DIR/$APP_NAME-macos.zip"

if [ ! -f "$LOCAL_TELEMETRY_CONFIG" ]; then
  cat <<EOF
Missing local telemetry config:
  $LOCAL_TELEMETRY_CONFIG

Create it from:
  Config/Telemetry.example.xcconfig

Set:
  ASSETFOX_TELEMETRY_API_KEY = <your Supabase Edge Function key>

This file is ignored by git and is required for internal telemetry-enabled builds.
EOF
  exit 1
fi

TELEMETRY_KEY="$(
  sed -n 's/^[[:space:]]*ASSETFOX_TELEMETRY_API_KEY[[:space:]]*=[[:space:]]*//p' "$LOCAL_TELEMETRY_CONFIG" | tail -n 1
)"

if [ -z "$TELEMETRY_KEY" ] || [ "$TELEMETRY_KEY" = "YOUR_SUPABASE_EDGE_FUNCTION_KEY_HERE" ]; then
  echo "Config/Telemetry.local.xcconfig does not contain a valid ASSETFOX_TELEMETRY_API_KEY value."
  exit 1
fi

cd "$ROOT_DIR"

xcodebuild \
  -project AssetFox.xcodeproj \
  -scheme AssetFox \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

mkdir -p "$DIST_DIR"
rm -rf "$APP_DEST" "$ZIP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

/usr/libexec/PlistBuddy -c "Set :AssetFoxTelemetryAPIKey $TELEMETRY_KEY" "$APP_DEST/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP_DEST" >/dev/null

ditto -c -k --keepParent "$APP_DEST" "$ZIP_DEST"

echo "Built:"
echo "  $APP_DEST"
echo "  $ZIP_DEST"
