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
dist/AssetFox-<version>-build<build>-self-contained/AssetFox.app
dist/AssetFox-<version>-build<build>-self-contained.zip
dist/AssetFox.app
dist/AssetFox-macos.zip
```

The built app is self-contained for telemetry configuration. The release script also requires executable FFmpeg/FFprobe tools before packaging. Put them at:

```text
AssetFox/Vendor/FFmpeg/ffmpeg
AssetFox/Vendor/FFmpeg/ffprobe
```

or set `ASSETFOX_FFMPEG_SOURCE_DIR` to a local folder containing both tools.

## Privacy boundary

Telemetry is intentionally limited to anonymous usage and diagnostic events. It must not collect:

- file names
- file paths
- media content
- project names
- raw FFmpeg output
- user-entered text

Users can disable anonymous analytics in the app's `About` section.
