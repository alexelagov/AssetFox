import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaInfoView: View {
    @State private var items: [MediaInfoItem] = []
    @State private var selectedID: UUID?
    @State private var isDropTargeted = false
    @State private var inspectionState: MediaInfoInspectionState = .idle

    private let inspector = MediaInfoInspector()
    private let primaryColumnWidth: CGFloat = 720
    private let sidebarWidth: CGFloat = 360

    private var selectedItem: MediaInfoItem? {
        guard let selectedID else { return items.first }
        return items.first(where: { $0.id == selectedID }) ?? items.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                workspaceSection
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selectedItem?.id) {
            await inspectSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Media Info", systemImage: "info.square")
                .font(.system(size: 28, weight: .semibold))

            Text("Inspect files and surface RAW families, containers, codecs, resolution, frame rate, duration, timecode, and color metadata.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            HStack(spacing: 10) {
                MediaInfoBadge(title: "\(items.count) File\(items.count == 1 ? "" : "s")", tint: items.isEmpty ? .gray : .blue)
                MediaInfoBadge(title: selectedItem == nil ? "No Selection" : "Summary Ready", tint: selectedItem == nil ? .gray : .green)
                MediaInfoBadge(title: inspectionState.badgeTitle, tint: inspectionState.badgeTint)
            }
        }
    }

    private var workspaceSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    sourcePanel
                    selectionPanel
                }
                .frame(width: primaryColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 24) {
                    summaryPanel
                    metadataPanel
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 24) {
                sourcePanel
                selectionPanel
                summaryPanel
                metadataPanel
            }
        }
    }

    private var sourcePanel: some View {
        MediaInfoPanel(title: "Source", headline: "Drop zone", subtitle: "Drop one or more files here, or choose them from disk.") {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isDropTargeted ? 0.08 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isDropTargeted ? Color.accentColor : Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                    )
                    .frame(height: 170)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

                            Text("Drop files to inspect")
                                .font(.headline.weight(.semibold))

                            Text("Supports single or multi-file selection with native media metadata inspection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))

                HStack(spacing: 10) {
                    Button("Choose Files", action: chooseFiles)
                        .buttonStyle(.borderedProminent)
                        .help("Open a native macOS file picker and add one or more files to Media Info.")

                    Button("Clear") {
                        items.removeAll()
                        selectedID = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                    .help("Clear the current Media Info selection.")
                }
            }
        }
    }

    private var selectionPanel: some View {
        MediaInfoPanel(title: "Selection", headline: "Chosen files", subtitle: "Review the files loaded into Media Info and switch the detail view.") {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No files selected yet.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Choose files or drop them into the panel above to inspect basic metadata.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            selectedID = item.id
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: item.kind.symbolName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(item.id == selectedID ? Color.accentColor : Color.secondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.url.path)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 12)

                                Text(item.formattedFileSize)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(item.id == selectedID ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(item.id == selectedID ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var summaryPanel: some View {
        MediaInfoPanel(title: "Summary", headline: "Selected file", subtitle: "Basic filesystem metadata for the currently selected item.") {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 12) {
                    MediaInfoRow(label: "Name", value: selectedItem.name)
                    MediaInfoRow(label: "Path", value: selectedItem.url.path, monospace: true)
                    MediaInfoRow(label: "Type", value: selectedItem.kind.displayName)
                    MediaInfoRow(label: "Extension", value: selectedItem.extensionLabel)
                    MediaInfoRow(label: "Size", value: selectedItem.formattedFileSize)
                    MediaInfoRow(label: "Created", value: selectedItem.createdAt)
                    MediaInfoRow(label: "Modified", value: selectedItem.modifiedAt)
                }
            } else {
                MediaInfoEmptyState(message: "Select a file to view its summary.")
            }
        }
    }

    private var metadataPanel: some View {
        MediaInfoPanel(title: "Metadata", headline: "Media attributes", subtitle: "Native inspection uses AVFoundation and ImageIO, with ffprobe enhancement for deeper RAW, container, codec, and stream details when available.") {
            switch inspectionState {
            case .idle:
                MediaInfoEmptyState(message: "Select a file to inspect its media metadata.")
            case .loading:
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Inspecting media metadata...")
                        .font(.headline.weight(.semibold))
                    Text("This runs off the main thread so you can keep browsing the selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label("Metadata inspection failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let metadata):
                VStack(alignment: .leading, spacing: 12) {
                    let sections = metadataSections(for: metadata, item: selectedItem)

                    ForEach(sections) { section in
                        MediaInfoInspectorSectionView(section: section)
                    }

                    let detectedCount = sections
                        .flatMap(\.rows)
                        .filter { !$0.isPlaceholder }
                        .count

                    if detectedCount <= 8 {
                        Text("This file exposed only partial metadata on this Mac. MXF often still yields container, duration, timecode, and audio even when codec, resolution, or color fields are not available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    if !metadata.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Warnings")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.secondary)

                            ForEach(metadata.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose Files for Media Info"
        panel.message = "Select one or more files to inspect."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .movie,
            .video,
            .audio,
            .image,
            .data,
            .content
        ]

        if panel.runModal() == .OK {
            append(urls: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    append(urls: [url])
                }
            }
            accepted = true
        }

        return accepted
    }

    private func append(urls: [URL]) {
        let newItems = urls
            .filter { $0.isFileURL }
            .compactMap(MediaInfoItem.init(url:))

        guard !newItems.isEmpty else { return }

        items = (items + newItems).uniqued(by: \.url)
        if selectedID == nil {
            selectedID = items.first?.id
        }
    }

    @MainActor
    private func inspectSelection() async {
        guard let selectedItem else {
            inspectionState = .idle
            return
        }

        inspectionState = .loading
        let result = await inspector.inspect(url: selectedItem.url)
        inspectionState = .loaded(result)
    }

    private func metadataSections(for metadata: MediaInfoInspectionResult, item: MediaInfoItem?) -> [MediaInfoInspectorSection] {
        if let deepMetadata = metadata.deepMetadata {
            var sections: [MediaInfoInspectorSection] = []

            sections.append(
                MediaInfoInspectorSection(
                    title: "General",
                    rows: [
                        .required("Complete name", deepMetadata.general.completeName ?? item?.url.path, monospace: true),
                        .required("Format", deepMetadata.general.containerFormat ?? metadata.container),
                        .optional("Format profile", deepMetadata.general.formatProfile),
                        .optional("Codec ID", deepMetadata.general.codecID),
                        .required("File size", deepMetadata.general.fileSize ?? item?.formattedFileSize),
                        .required("Duration", deepMetadata.general.duration ?? metadata.duration),
                        .optional("Overall bit rate mode", deepMetadata.general.overallBitRateMode),
                        .optional("Overall bit rate", deepMetadata.general.overallBitRate ?? metadata.overallBitRate),
                        .optional("Frame rate", deepMetadata.general.frameRate ?? metadata.frameRate),
                        .optional("Encoded date", deepMetadata.general.encodedDate ?? metadata.encodedDate),
                        .optional("Tagged date", deepMetadata.general.taggedDate ?? metadata.taggedDate),
                        .optional("Writing application", deepMetadata.general.writingApplication ?? metadata.writingApplication),
                        .optional("Writing library", deepMetadata.general.writingLibrary ?? metadata.writingLibrary)
                    ]
                )
            )

            sections.append(contentsOf: deepMetadata.videoTracks.map { track in
                MediaInfoInspectorSection(
                    title: "Video",
                    subtitle: deepMetadata.videoTracks.count > 1 ? "#\(track.index + 1)" : nil,
                    rows: [
                        .optional("ID", track.streamID),
                        .required("Format", track.format),
                        .optional("Format version", track.formatVersion),
                        .optional("Format profile", track.formatProfile),
                        .optional("Codec ID", track.codecID ?? track.codec),
                        .required("Duration", track.duration ?? metadata.duration),
                        .optional("Bit rate mode", track.bitRateMode),
                        .optional("Bit rate", track.bitRate),
                        .required("Width", track.width.map { "\($0) pixels" }),
                        .required("Height", track.height.map { "\($0) pixels" }),
                        .optional("Display aspect ratio", track.displayAspectRatio),
                        .optional("Frame rate mode", track.frameRateMode),
                        .required("Frame rate", track.frameRate ?? metadata.frameRate),
                        .optional("Color space", track.colorSpace ?? metadata.colorSpace),
                        .optional("Chroma subsampling", track.chromaSubsampling),
                        .optional("Scan type", track.scanType),
                        .optional("Bits/(Pixel*Frame)", track.bitsPerPixelFrame),
                        .optional("Stream size", track.streamSize),
                        .optional("Writing library", track.writingLibrary ?? metadata.writingLibrary),
                        .optional("Encoded date", track.encodedDate ?? metadata.encodedDate),
                        .optional("Tagged date", track.taggedDate ?? metadata.taggedDate),
                        .optional("Bit depth", track.bitDepth ?? metadata.bitDepth),
                        .optional("Timecode", track.timecode ?? metadata.timecode),
                        .optional("Pixel format", track.pixelFormat ?? metadata.pixelFormat),
                        .optional("Color primaries", track.colorPrimaries ?? metadata.colorPrimaries),
                        .optional("Matrix coefficients", track.matrixCoefficients),
                        .optional("Gamma", track.gamma)
                    ]
                )
            })

            sections.append(contentsOf: deepMetadata.audioTracks.map { track in
                MediaInfoInspectorSection(
                    title: "Audio",
                    subtitle: deepMetadata.audioTracks.count > 1 ? "#\(track.index + 1)" : nil,
                    rows: [
                        .optional("ID", track.streamID),
                        .required("Format", track.format),
                        .optional("Format settings", track.formatSettings),
                        .required("Codec ID", track.codecID ?? track.codec),
                        .required("Duration", track.duration ?? metadata.duration),
                        .optional("Bit rate mode", track.bitRateMode),
                        .optional("Bit rate", track.bitRate),
                        .required("Channel(s)", track.channelCount),
                        .optional("Channel layout", track.channelLayout),
                        .required("Sampling rate", track.sampleRate),
                        .optional("Bit depth", track.bitDepth),
                        .optional("Stream size", track.streamSize),
                        .optional("Default", track.defaultFlag),
                        .optional("Alternate group", track.alternateGroup),
                        .optional("Encoded date", track.encodedDate ?? metadata.encodedDate),
                        .optional("Tagged date", track.taggedDate ?? metadata.taggedDate)
                    ]
                )
            })

            return sections
        }

        return [
            MediaInfoInspectorSection(
                title: "General",
                rows: [
                    .required("Complete name", item?.url.path, monospace: true),
                    .required("Format", metadata.container),
                    .optional("Format profile", metadata.profile),
                    .required("File size", item?.formattedFileSize),
                    .required("Duration", metadata.duration),
                    .optional("Overall bit rate", metadata.overallBitRate),
                    .optional("Encoded date", metadata.encodedDate),
                    .optional("Tagged date", metadata.taggedDate),
                    .optional("Writing application", metadata.writingApplication),
                    .optional("Writing library", metadata.writingLibrary)
                ]
            ),
            MediaInfoInspectorSection(
                title: "Video",
                rows: [
                    .required("Codec", metadata.codec),
                    .required("Resolution", metadata.resolution),
                    .required("Frame rate", metadata.frameRate),
                    .optional("Timecode", metadata.timecode),
                    .optional("Bit depth", metadata.bitDepth),
                    .optional("Pixel format", metadata.pixelFormat),
                    .optional("Color space", metadata.colorSpace),
                    .optional("Transfer function", metadata.transferFunction),
                    .optional("Color primaries", metadata.colorPrimaries),
                    .optional("Color range", metadata.colorRange)
                ]
            ),
            MediaInfoInspectorSection(
                title: "Audio",
                rows: [
                    .required("Summary", metadata.audioSummary)
                ]
            )
        ]
    }
}

struct MediaInfoItem: Identifiable {
    enum Kind {
        case image
        case movie
        case audio
        case data

        var displayName: String {
            switch self {
            case .image: return "Image"
            case .movie: return "Movie"
            case .audio: return "Audio"
            case .data: return "File"
            }
        }

        var symbolName: String {
            switch self {
            case .image: return "photo"
            case .movie: return "film"
            case .audio: return "waveform"
            case .data: return "doc"
            }
        }
    }

    let id = UUID()
    let url: URL
    let kind: Kind
    let name: String
    let fileSize: Int64
    let createdAt: String
    let modifiedAt: String

    init?(url: URL) {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .contentTypeKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey
            ])
        } catch {
            return nil
        }

        guard values.isRegularFile == true else { return nil }

        let type = values.contentType
        if type?.conforms(to: .image) == true {
            kind = .image
        } else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            kind = .movie
        } else if type?.conforms(to: .audio) == true {
            kind = .audio
        } else {
            kind = .data
        }

        self.url = url
        self.name = url.lastPathComponent
        self.fileSize = Int64(values.fileSize ?? 0)
        self.createdAt = Self.dateFormatter.string(from: values.creationDate ?? .distantPast)
        self.modifiedAt = Self.dateFormatter.string(from: values.contentModificationDate ?? .distantPast)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var extensionLabel: String {
        url.pathExtension.isEmpty ? "None" : url.pathExtension.uppercased()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum MediaInfoInspectionState {
    case idle
    case loading
    case loaded(MediaInfoInspectionResult)
    case failed(String)

    var badgeTitle: String {
        switch self {
        case .idle:
            return "Awaiting Selection"
        case .loading:
            return "Inspecting Metadata"
        case .loaded(let result):
            return result.metadataSource.contains("ffprobe") ? "Enhanced Metadata Ready" : "Metadata Ready"
        case .failed:
            return "Metadata Error"
        }
    }

    var badgeTint: Color {
        switch self {
        case .idle:
            return .gray
        case .loading:
            return .blue
        case .loaded(let result):
            return result.warnings.isEmpty ? .green : .orange
        case .failed:
            return .red
        }
    }
}

private struct MediaInfoPanel<Content: View>: View {
    let title: String
    let headline: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(headline)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(0.05))
        )
    }
}

private struct MediaInfoBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .foregroundStyle(tint == .gray ? Color.secondary : tint)
    }
}

private struct MediaInfoRow: View {
    let label: String
    let value: String
    var monospace = false
    var isPlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: monospace ? .monospaced : .default))
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct MediaInfoEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct MediaInfoInspectorSection: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String?
    let rows: [MediaInfoInspectorField]
}

private struct MediaInfoInspectorField: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var monospace = false
    var isPlaceholder = false

    static func required(_ label: String, _ value: String?, monospace: Bool = false) -> Self {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = normalized?.isEmpty == false ? normalized! : "Not detected"
        return Self(label: label, value: detected, monospace: monospace, isPlaceholder: normalized?.isEmpty != false)
    }

    static func optional(_ label: String, _ value: String?, monospace: Bool = false) -> Self {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = normalized?.isEmpty == false ? normalized! : "Not detected"
        return Self(label: label, value: detected, monospace: monospace, isPlaceholder: normalized?.isEmpty != false)
    }
}

private struct MediaInfoInspectorSectionView: View {
    let section: MediaInfoInspectorSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.secondary)

                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 132, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 13, weight: .semibold, design: row.monospace ? .monospaced : .default))
                            .foregroundStyle(row.isPlaceholder ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear)

                    if index < section.rows.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.04))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
