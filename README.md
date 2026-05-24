# AssetFox

Version: `0.4.3`
Build: `12`
Channel: `Alpha MVP`
Platform: `macOS 15+`

AssetFox is a native macOS post-production toolkit for checking, collecting, ingesting, and inspecting media files. It is built as a single desktop app with a sidebar workflow for post-production operators.

## Repository Status

This repository is prepared for public visibility with telemetry secrets and release artifacts kept out of the tracked source tree. Before changing GitHub visibility, run the [Public Repository Checklist](docs/PUBLIC_RELEASE_CHECKLIST.md).

## Main Features

- `Quality Check`: compare multiple video exports with synchronized playback, frame stepping, reference-based cut checks, black/freeze detection, timeline findings, raw FFmpeg diagnostics, and TXT export of QC results.
- `Ingest`: copy files from multiple sources to a destination with preflight checks, optional SHA-256 verification, conflict handling, cancellation, partial progress preservation, and TXT/CSV/JSON reports.
- `Duplicate Finder`: scan folders for exact duplicate files, review duplicate sets, quarantine or trash selected duplicates, and export CSV results.
- `Collect Media`: collect media from Premiere FCP XML or native `.prproj` files, filter FCP XML paths to supported media assets, merge XML/project references, relink sources, and report missing or skipped media.
- `Media Info`: inspect technical metadata for video, audio, image, RAW, MOV, MXF, and other media files, with compare mode for checking differences between files.
- `About`: show version/build, MediaInfoLib status, FFmpeg/ffprobe availability, and anonymous analytics controls.

## Current Release Notes

`0.4.3` / build `12` focuses on release hardening:

- FCP XML collection is restricted to supported media extensions through `CollectMediaPathFilter`.
- Unsupported FCP XML file URLs are skipped with the report reason `unsupported media extension ignored`.
- Parser security coverage lives in `Tests/CollectMediaXMLParserSecurityTests.swift`.
- `script/test_collect_media_xml_parser.sh` runs the standalone parser security test.
- Internal release builds use `script/build_release.sh` for versioned self-contained artifacts.
- Privacy-conscious telemetry is anonymous, opt-out capable, and does not collect file names, file paths, media content, project names, raw FFmpeg output, or user-entered text.

## Build And Transfer

For quick local packaging on machines without a full Xcode release setup:

```bash
bash build.sh
```

The legacy package script creates:

- `~/Desktop/AssetFox.app`
- `~/Desktop/AssetFox-macos.zip`

For internal self-contained release builds, configure telemetry and FFmpeg tools first, then run:

```bash
./script/build_release.sh
```

The release script creates versioned artifacts:

```text
dist/AssetFox-<version>-build<build>-self-contained/AssetFox.app
dist/AssetFox-<version>-build<build>-self-contained.zip
dist/AssetFox.app
dist/AssetFox-macos.zip
```

The app bundle is ad-hoc signed before zipping. For transfer to another Mac, copy the zip, unzip it, and open the app. If Gatekeeper blocks first launch, use `Open Anyway` in macOS Security settings.

## Development Notes

- Open `AssetFox.xcodeproj` in Xcode for full IDE work.
- The app uses one macOS window with a `NavigationSplitView` sidebar.
- Root navigation lives in `AssetFox/Sources/Root`.
- `Quality Check` lives under `AssetFox/Sources/QualityCheck`.
- `Collect Media` contracts, parsers, services, view models, and views live under `AssetFox/Sources/CollectMedia`.
- `Ingest` lives under `AssetFox/Sources/Ingest`.
- `Media Info` lives under `AssetFox/Sources/MediaInfo`.
- Runtime lookup helpers live under `AssetFox/Sources/Runtime`.
- Anonymous analytics lives under `AssetFox/Sources/Telemetry`.
- No Python runtime is embedded in the macOS app target.

## Verification

Run the Collect Media parser security test:

```bash
script/test_collect_media_xml_parser.sh
```

See [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md) for the full launch and feature checklist.

## Supporting Docs

- [Smoke Test](docs/SMOKE_TEST.md)
- [FFmpeg Tool Placement](docs/FFmpeg-Tools.md)
- [MediaInfoLib Embedding](docs/MediaInfoLib-Embedding.md)
- [Telemetry Build Setup](docs/telemetry-build.md)
- [Public Repository Checklist](docs/PUBLIC_RELEASE_CHECKLIST.md)

## Layout

```text
AssetFox/
├── AssetFox.xcodeproj/
├── AssetFox/
│   ├── Sources/
│   │   ├── Root/
│   │   ├── QualityCheck/
│   │   ├── CollectMedia/
│   │   ├── Ingest/
│   │   ├── MediaInfo/
│   │   ├── Runtime/
│   │   ├── Telemetry/
│   │   ├── Models/
│   │   ├── Services/
│   │   └── Views/
│   └── Info.plist
├── docs/
├── script/
├── Tests/
├── build.sh
└── README.md
```
