import SwiftUI

struct AssetFoxRootView: View {
    @State private var selection: TopLevelTab = .duplicateFinder

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tabItem {
                    Label("Duplicate Finder", systemImage: "doc.on.doc")
                }
                .tag(TopLevelTab.duplicateFinder)

            CollectMediaView()
                .tabItem {
                    Label("Collect Media", systemImage: "shippingbox")
                }
                .tag(TopLevelTab.collectMedia)

            IngestView()
                .tabItem {
                    Label("Ingest", systemImage: "square.and.arrow.down.on.square")
                }
                .tag(TopLevelTab.ingest)

            MediaInfoView()
                .tabItem {
                    Label("Media Info", systemImage: "info.square")
                }
                .tag(TopLevelTab.mediaInfo)

            AssetFoxAboutView()
                .tabItem {
                    Label("About", systemImage: "sparkles.rectangle.stack")
                }
                .tag(TopLevelTab.about)
        }
    }
}

private enum TopLevelTab: Hashable {
    case duplicateFinder
    case collectMedia
    case ingest
    case mediaInfo
    case about
}

private struct AssetFoxAboutView: View {
    private let cardFill = Color.white.opacity(0.04)
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    @State private var runtimeStatus = MediaInfoRuntimeStatus.snapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.system(size: 28, weight: .semibold))

                    Text("AssetFox build information and bundled runtime status.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    aboutBadge("Version \(appVersion)", tint: .blue)
                    aboutBadge("Build \(buildNumber)", tint: .green)
                    aboutBadge(runtimeStatus.bundled ? "MediaInfoLib Bundled" : "MediaInfoLib Missing", tint: runtimeStatus.bundled ? .green : .orange)
                    aboutBadge(runtimeStatus.loaded ? "Runtime Loaded" : "Runtime Not Loaded", tint: runtimeStatus.loaded ? .green : .orange)
                }

                HStack(alignment: .top, spacing: 24) {
                    aboutCard(
                        title: "Application",
                        rows: [
                            ("Name", "AssetFox"),
                            ("Version", appVersion),
                            ("Build", buildNumber),
                            ("Platform", "macOS")
                        ]
                    )

                    aboutCard(
                        title: "Runtime",
                        rows: [
                            ("MediaInfoLib", runtimeStatus.bundled ? "Embedded in app bundle" : "Not found in Contents/Frameworks"),
                            ("Runtime status", runtimeStatus.loaded ? "Loaded successfully" : "Failed to load"),
                            ("Inspector backend", "MediaInfoLib-first, then AVFoundation/ImageIO + ffprobe fallback"),
                            ("Minimum macOS", "15.0")
                        ]
                    )
                }

                if let runtimeError = runtimeStatus.error {
                    aboutCard(
                        title: "MediaInfoLib Load Error",
                        rows: [
                            ("Last error", runtimeError)
                        ]
                    )
                }
            }
            .frame(maxWidth: 1104)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            runtimeStatus = MediaInfoRuntimeStatus.snapshot()
        }
    }

    private func aboutCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(row.1)
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
        )
    }

    private func aboutBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.18))
            )
            .foregroundStyle(tint)
    }
}

private struct MediaInfoRuntimeStatus {
    let bundled: Bool
    let loaded: Bool
    let error: String?

    static func snapshot() -> MediaInfoRuntimeStatus {
        let payload = MediaInfoLibBridge.runtimeStatus()
        let bundled = payload["bundled"] as? Bool ?? false
        let loaded = payload["loaded"] as? Bool ?? false
        let errors = payload["errors"] as? [String] ?? []

        return MediaInfoRuntimeStatus(
            bundled: bundled,
            loaded: loaded,
            error: errors.first
        )
    }
}
