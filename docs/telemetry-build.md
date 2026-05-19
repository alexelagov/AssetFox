# Telemetry Build Setup

AssetFox telemetry uses a first-party Supabase Edge Function endpoint and a shared internal key. Do not commit the real key.

## Local build key

Copy the example config:

```bash
cp Config/Telemetry.example.xcconfig Config/Telemetry.local.xcconfig
```

Edit `Config/Telemetry.local.xcconfig`:

```xcconfig
ASSETFOX_TELEMETRY_API_KEY = <your Supabase Edge Function key>
```

`Config/Telemetry.local.xcconfig` is ignored by git.

## Supabase secret

The same key must be configured in Supabase:

```text
ASSETFOX_TELEMETRY_KEY = <your Supabase Edge Function key>
```

Set it in the Supabase dashboard under the project's Edge Function secrets.

## Release build

Run:

```bash
./script/build_release.sh
```

The script builds with Xcode without exposing the key to Xcode build settings, injects the local telemetry key into the copied app bundle, re-signs the app, and writes:

```text
dist/AssetFox.app
dist/AssetFox-macos.zip
```

The built app is self-contained for telemetry configuration. FFmpeg/FFprobe are self-contained only when the binaries exist at `AssetFox/Vendor/FFmpeg/ffmpeg` and `AssetFox/Vendor/FFmpeg/ffprobe` before building.
