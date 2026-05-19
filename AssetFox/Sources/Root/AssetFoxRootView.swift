import SwiftUI

struct AssetFoxRootView: View {
    @State private var selectedSectionRawValue = AssetFoxSection.qualityCheck.rawValue
    @State private var didTrackLaunch = false

    private var selectedSection: AssetFoxSection {
        AssetFoxSection(rawValue: selectedSectionRawValue) ?? .qualityCheck
    }

    private var selectedSectionBinding: Binding<AssetFoxSection?> {
        Binding(
            get: { AssetFoxSection(rawValue: selectedSectionRawValue) ?? .qualityCheck },
            set: { newSection in
                let section = newSection ?? .qualityCheck
                guard selectedSectionRawValue != section.rawValue else { return }
                selectedSectionRawValue = section.rawValue
                trackSectionOpen(section)
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedSectionBinding) {
                Section("Tools") {
                    ForEach(AssetFoxSection.toolSections) { section in
                        AssetFoxSidebarRow(section: section)
                            .tag(section as AssetFoxSection?)
                    }
                }

                Section("Application") {
                    ForEach(AssetFoxSection.applicationSections) { section in
                        AssetFoxSidebarRow(section: section)
                            .tag(section as AssetFoxSection?)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("AssetFox")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            persistentDetailViews
                .navigationTitle(selectedSection.title)
        }
        .focusedSceneValue(\.assetFoxSectionSelection, selectedSectionBinding)
        .task {
            guard !didTrackLaunch else { return }
            didTrackLaunch = true
            await TelemetryService.shared.track(.appLaunched)
            await TelemetryService.shared.track(.sectionOpened, properties: [
                "section": .string(selectedSection.telemetryName)
            ])
        }
    }

    @ViewBuilder
    private var persistentDetailViews: some View {
        ZStack {
            ForEach(AssetFoxSection.allCases) { section in
                detailView(for: section)
                    .opacity(section == selectedSection ? 1 : 0)
                    .allowsHitTesting(section == selectedSection)
                    .accessibilityHidden(section != selectedSection)
                    .zIndex(section == selectedSection ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: AssetFoxSection) -> some View {
        switch section {
        case .duplicateFinder:
            ContentView()
        case .collectMedia:
            CollectMediaView()
        case .qualityCheck:
            QualityCheckView()
        case .ingest:
            IngestView()
        case .mediaInfo:
            MediaInfoView()
        case .about:
            AssetFoxAboutView()
        }
    }

    private func trackSectionOpen(_ section: AssetFoxSection) {
        Task {
            await TelemetryService.shared.track(.sectionOpened, properties: [
                "section": .string(section.telemetryName)
            ])
        }
    }
}

enum AssetFoxSection: String, CaseIterable, Identifiable {
    case duplicateFinder
    case collectMedia
    case qualityCheck
    case ingest
    case mediaInfo
    case about

    var id: Self { self }

    static let toolSections: [AssetFoxSection] = [
        .qualityCheck,
        .ingest,
        .duplicateFinder,
        .collectMedia,
        .mediaInfo
    ]

    static let applicationSections: [AssetFoxSection] = [
        .about
    ]

    var title: String {
        switch self {
        case .duplicateFinder:
            "Duplicate Finder"
        case .collectMedia:
            "Collect Media"
        case .qualityCheck:
            "Quality Check"
        case .ingest:
            "Ingest"
        case .mediaInfo:
            "Media Info"
        case .about:
            "About"
        }
    }

    var detail: String {
        switch self {
        case .duplicateFinder:
            "Find duplicate files"
        case .collectMedia:
            "Collect Premiere media"
        case .qualityCheck:
            "Compare video exports"
        case .ingest:
            "Copy and verify sources"
        case .mediaInfo:
            "Inspect media metadata"
        case .about:
            "Version and runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .duplicateFinder:
            "doc.on.doc"
        case .collectMedia:
            "shippingbox"
        case .qualityCheck:
            "rectangle.split.3x1"
        case .ingest:
            "square.and.arrow.down.on.square"
        case .mediaInfo:
            "info.square"
        case .about:
            "sparkles.rectangle.stack"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .qualityCheck:
            "1"
        case .ingest:
            "2"
        case .duplicateFinder:
            "3"
        case .collectMedia:
            "4"
        case .mediaInfo:
            "5"
        case .about:
            "6"
        }
    }

    var telemetryName: String {
        switch self {
        case .qualityCheck:
            "quality_check"
        case .duplicateFinder:
            "duplicate_finder"
        case .collectMedia:
            "collect_media"
        case .ingest:
            "ingest"
        case .mediaInfo:
            "media_info"
        case .about:
            "about"
        }
    }
}

enum AssetFoxDesign {
    static let primaryColumnWidth: CGFloat = 704
    static let sidebarWidth: CGFloat = 360
    static let workspaceSpacing: CGFloat = 20
    static let pageMaxWidth: CGFloat = primaryColumnWidth + sidebarWidth + workspaceSpacing
    static let pageHorizontalPadding: CGFloat = 28
    static let pageVerticalPadding: CGFloat = 24
    static let panelPadding: CGFloat = 20
    static let panelRadius: CGFloat = 8
    static let innerRadius: CGFloat = 8
}

struct AssetFoxPageHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AssetFoxDesign.panelRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }

            accessory
        }
    }
}

extension AssetFoxPageHeader where Accessory == EmptyView {
    init(title: String, systemImage: String, subtitle: String) {
        self.init(title: title, systemImage: systemImage, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct AssetFoxPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: AssetFoxDesign.panelRadius, style: .continuous)

        panelShape
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(surfaceLift)
            .clipShape(panelShape)
            .overlay(
                panelShape.strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 14, x: 0, y: 6)
    }

    private var surfaceLift: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.015)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.11)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.black.opacity(0.10)
    }
}

private struct AssetFoxSidebarRow: View {
    let section: AssetFoxSection

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)

                Text(section.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AssetFoxSectionSelectionKey: FocusedValueKey {
    typealias Value = Binding<AssetFoxSection?>
}

extension FocusedValues {
    var assetFoxSectionSelection: Binding<AssetFoxSection?>? {
        get { self[AssetFoxSectionSelectionKey.self] }
        set { self[AssetFoxSectionSelectionKey.self] = newValue }
    }
}

private struct AssetFoxAboutView: View {
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    @State private var runtimeStatus = MediaInfoRuntimeStatus.snapshot()
    @State private var ffmpegStatus = FFmpegRuntimeResolver.snapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AssetFoxPageHeader(
                    title: "About",
                    systemImage: "sparkles.rectangle.stack",
                    subtitle: "AssetFox build information and bundled runtime status."
                ) {
                    HStack(spacing: 10) {
                        aboutBadge("Version \(appVersion)", tint: .blue)
                        aboutBadge("Build \(buildNumber)", tint: .green)
                        aboutBadge(runtimeStatus.bundled ? "MediaInfoLib Bundled" : "MediaInfoLib Missing", tint: runtimeStatus.bundled ? .green : .orange)
                        aboutBadge(runtimeStatus.loaded ? "Runtime Loaded" : "Runtime Not Loaded", tint: runtimeStatus.loaded ? .green : .orange)
                        aboutBadge(ffmpegStatus.ffmpeg.isAvailable ? "ffmpeg Ready" : "ffmpeg Missing", tint: ffmpegStatus.ffmpeg.isAvailable ? .green : .orange)
                        aboutBadge(ffmpegStatus.ffprobe.isAvailable ? "ffprobe Ready" : "ffprobe Missing", tint: ffmpegStatus.ffprobe.isAvailable ? .green : .orange)
                    }
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

                    aboutCard(
                        title: "FFmpeg Tools",
                        rows: [
                            ("ffmpeg", "\(ffmpegStatus.ffmpeg.source.rawValue): \(ffmpegStatus.ffmpeg.displayPath)"),
                            ("ffprobe", "\(ffmpegStatus.ffprobe.source.rawValue): \(ffmpegStatus.ffprobe.displayPath)"),
                            ("Bundle path", "Contents/Resources/Tools"),
                            ("Licensing mode", "LGPL-compatible builds preferred")
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

                telemetryCard
            }
            .frame(maxWidth: 1104)
            .padding(.horizontal, AssetFoxDesign.pageHorizontalPadding)
            .padding(.vertical, AssetFoxDesign.pageVerticalPadding)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            runtimeStatus = MediaInfoRuntimeStatus.snapshot()
            ffmpegStatus = FFmpegRuntimeResolver.snapshot()
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
            AssetFoxPanelBackground()
        )
    }

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analytics".uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            AssetFoxTelemetrySettingsView()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AssetFoxPanelBackground()
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
