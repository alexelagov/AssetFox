# AssetFox

Merged macOS app with two top-level tabs:

- `DuplicateFinder`
- `Collect Media`

`DuplicateFinder` remains the baseline visual/architectural shell. `Collect Media` is being ported natively to SwiftUI and Swift services, with Python excluded from the final app target.
`Collect Media` now has native Swift service and SwiftUI layers in the new target, but this machine cannot perform a full compile verification because it does not have a full Xcode install.

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
