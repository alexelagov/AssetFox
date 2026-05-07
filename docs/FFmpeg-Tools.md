# FFmpeg tool placement

AssetFox Quality Check can use bundled `ffmpeg` and `ffprobe` tools, but the app must also build and run when those tools are not present.

## Vendor layout

Place approved local FFmpeg tools here before building:

```text
AssetFox/Vendor/FFmpeg/ffmpeg
AssetFox/Vendor/FFmpeg/ffprobe
```

The Xcode build phase copies executable files from that vendor folder into the app bundle:

```text
AssetFox.app/Contents/Resources/Tools/ffmpeg
AssetFox.app/Contents/Resources/Tools/ffprobe
```

If either file is missing, the build prints a warning and continues. Runtime lookup then falls back to:

```text
/opt/homebrew/bin/ffmpeg
/opt/homebrew/bin/ffprobe
/usr/local/bin/ffmpeg
/usr/local/bin/ffprobe
```

## Licensing requirement

Do not commit FFmpeg binaries unless licensing has been explicitly reviewed and approved for the release. Prefer LGPL-compatible FFmpeg builds for AssetFox distribution.

Before bundling tools, confirm that the build avoids GPL-only components and options such as `--enable-gpl` unless the distribution plan explicitly accepts GPL obligations. Keep the corresponding license notices and source/build information with the release materials.
