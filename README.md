# AssetFox

Version: `0.2.0`  
Channel: `Alpha MVP`

Merged macOS app with four top-level tabs:

- `DuplicateFinder`
- `Collect Media`
- `Ingest`
- `Media Info`

`DuplicateFinder` remains the baseline visual/architectural shell. `Collect Media` has been ported natively to SwiftUI and Swift services with Python excluded from the final app target. `Ingest` is now part of the MVP and includes source scanning, preflight validation, recursive copy, optional SHA-256 verification, optional report generation, cancellation, and result reporting. `Media Info` adds deep inspection, MediaInfoLib-backed metadata, comparison mode, and metadata export for post-production media.

## Build And Transfer

This repository includes a local packaging script that does not rely on `xcodebuild`, which matters on this machine because only Command Line Tools are installed.

```bash
bash build.sh
```

The script creates:

- `~/Desktop/AssetFox.app`
- `~/Desktop/AssetFox-macos.zip`

The app bundle is ad-hoc signed before the zip is produced. For transfer to another Mac, copy the zip, unzip it, and open the app. If Gatekeeper blocks first launch, use `Open Anyway` in macOS Security settings.

## Development Notes

- Open `AssetFox.xcodeproj` in Xcode for full IDE work.
- The merged app uses one window with a `TabView` at the root.
- The `Collect Media` feature contract is frozen in `AssetFox/Sources/CollectMedia/Models/CollectMediaContracts.swift`.
- The `Collect Media` backend lives under `AssetFox/Sources/CollectMedia/Services`.
- The `Collect Media` SwiftUI tab lives under `AssetFox/Sources/CollectMedia/ViewModels` and `AssetFox/Sources/CollectMedia/Views`.
- The `Ingest` workflow lives under `AssetFox/Sources/Ingest`.
- The `Media Info` workflow lives under `AssetFox/Sources/MediaInfo`.
- No Python runtime is embedded in the merged macOS target.

## Smoke Test

See [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md) for the launch and feature checklist.

## Layout

```text
MediaToolkit/
├── AssetFox.xcodeproj/
├── AssetFox/
│   ├── Sources/
│   │   ├── Root/
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── Views/
│   │   └── CollectMedia/
│   └── Info.plist
├── build.sh
└── README.md
```
