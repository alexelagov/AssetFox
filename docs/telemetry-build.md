# Telemetry Build Setup

AssetFox telemetry uses a first-party Supabase Edge Function endpoint and a shared internal key. Do not commit the real endpoint or key.

The tracked app configuration intentionally leaves telemetry unconfigured for public/default builds. Internal release builds inject telemetry settings from `Config/Telemetry.local.xcconfig` after the app bundle is copied into `dist/`.

## Local build key

Copy the example config:

```bash
cp Config/Telemetry.example.xcconfig Config/Telemetry.local.xcconfig
```

Edit `Config/Telemetry.local.xcconfig`:

```xcconfig
ASSETFOX_TELEMETRY_API_KEY = <your Supabase Edge Function key>
ASSETFOX_TELEMETRY_ENDPOINT_URL = <your Supabase Edge Function HTTPS URL>
```

`Config/Telemetry.local.xcconfig` is ignored by git.

## Supabase secret

The same key must be configured in Supabase:

```text
ASSETFOX_TELEMETRY_KEY = <your Supabase Edge Function key>
```

Set it in the Supabase dashboard under the project's Edge Function secrets.

Do not use a Supabase service-role key or unrestricted backend secret in a desktop app bundle. Treat any value shipped inside `AssetFox.app` as recoverable by users and enforce authorization, validation, and rate limits in the Edge Function.

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

## Public repository boundary

Before making the repository public, run the [Public Repository Checklist](PUBLIC_RELEASE_CHECKLIST.md). Rotate any telemetry key that may have appeared in terminal logs, screenshots, or old commits.
