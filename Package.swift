// swift-tools-version: 6.0
// Headless CLI target. Builds with plain Command Line Tools (`swift build`);
// the AssetFox.xcodeproj app target does not use this manifest.
import PackageDescription

let package = Package(
    name: "AssetFox",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "assetfox-cli", targets: ["AssetFoxCLI"])
    ],
    targets: [
        .executableTarget(
            name: "AssetFoxCLI",
            path: ".",
            exclude: [
                "LICENSE",
                "README.md",
                "SECURITY.md",
                "build.sh",
                "Config",
                "docs",
                "script",
                "AssetFox.xcodeproj",
                "AssetFox/Info.plist",
                "AssetFox/AssetFox.entitlements",
                "AssetFox/AssetFox-Bridging-Header.h",
                "AssetFox/OpenSourceLicenses.txt",
                "AssetFox/Assets.xcassets",
                "AssetFox/Vendor/FFmpeg",
                "AssetFox/Vendor/MediaInfoLib/Developpers",
                "AssetFox/Vendor/MediaInfoLib/License.html",
                "AssetFox/Vendor/MediaInfoLib/README.md",
                "AssetFox/Vendor/MediaInfoLib/Changes.txt",
                "AssetFox/Vendor/MediaInfoLib/ReadMe.txt",
                "AssetFox/Vendor/MediaInfoLib/History.txt",
                "AssetFox/Vendor/MediaInfoLib/libmediainfo.dylib",
                "AssetFox/Sources/CollectMedia/Services/CollectMediaSequenceDetector.swift",
                "AssetFox/Sources/AssetFoxApp.swift",
                "AssetFox/Sources/Root",
                "AssetFox/Sources/Views",
                "AssetFox/Sources/Models",
                "AssetFox/Sources/Services",
                "AssetFox/Sources/Ingest",
                "AssetFox/Sources/Telemetry",
                "AssetFox/Sources/CollectMedia/Models",
                "AssetFox/Sources/CollectMedia/ViewModels",
                "AssetFox/Sources/CollectMedia/Views",
                "AssetFox/Sources/CollectMedia/Services/CollectMediaCollector.swift",
                "AssetFox/Sources/CollectMedia/Services/CollectMediaRelinker.swift",
                "AssetFox/Sources/CollectMedia/Services/CollectMediaService.swift",
                "AssetFox/Sources/CollectMedia/Services/CollectMediaXMLParser.swift",
                "AssetFox/Sources/MediaInfo/MediaInfoView.swift",
                "AssetFox/Sources/MediaInfo/MediaInfoLibBridge.h",
                "AssetFox/Sources/MediaInfo/MediaInfoLibBridge.mm",
                "AssetFox/Sources/QualityCheck/ViewModels",
                "AssetFox/Sources/QualityCheck/Views"
            ],
            sources: [
                "AssetFox/Sources/MediaInfo/MediaInfoModels.swift",
                "AssetFox/Sources/MediaInfo/MediaInfoLibService.swift",
                "AssetFox/Sources/MediaInfo/MediaInfoInspector.swift",
                "AssetFox/Sources/MediaInfo/PixelFormatBitDepth.swift",
                "AssetFox/Sources/CollectMedia/Services/FFProbeAdapter.swift",
                "AssetFox/Sources/QualityCheck/Models/QualityCheckModels.swift",
                "AssetFox/Sources/QualityCheck/Services/QualityCheckAnalyzer.swift",
                "AssetFox/Sources/Runtime/FFmpegRuntimeResolver.swift",
                "cli/Sources/MediaInfoLibBridgeShim.swift",
                "cli/Sources/CLIOutput.swift",
                "cli/Sources/CLIMediaItemLoader.swift",
                "cli/Sources/CLIPassportEncoder.swift",
                "cli/Sources/CLIInspectCommand.swift",
                "cli/Sources/CLIQualityCheckCommand.swift",
                "cli/Sources/CLIDoctorCommand.swift",
                "cli/Sources/main.swift"
            ],
            resources: [
                .copy("AssetFox/Vendor/MediaInfoLib/libmediainfo.0.dylib")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        // Test RUNNER, not a testTarget: this machine builds with plain
        // Command Line Tools (see the header), which ship neither XCTest nor
        // swift-testing, so `swift test` cannot compile a test bundle here.
        // The @main runner exits non-zero on the first failed assertion;
        // run it with `swift run assetfox-tests` (build.sh does).
        //
        // The parser under test is app-target code the CLI deliberately
        // excludes, so this target compiles it directly through the symlinks
        // in Tests/Compiled (plus the contracts file it needs); the test
        // file carries the one-struct CollectReportRow shim the parser
        // expects from the app's collector.
        .executableTarget(
            name: "assetfox-tests",
            path: "Tests",
            sources: [
                "CollectMediaXMLParserSecurityTests.swift",
                "PixelFormatBitDepthTests.swift",
                "Compiled/CollectMediaXMLParser.swift",
                "Compiled/CollectMediaContracts.swift",
                "Compiled/PixelFormatBitDepth.swift"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
