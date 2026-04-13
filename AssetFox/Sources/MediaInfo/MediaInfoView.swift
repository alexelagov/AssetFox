import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaInfoView: View {
    @State private var items: [MediaInfoItem] = []
    @State private var selectedID: UUID?
    @State private var presentationMode: MediaInfoPresentationMode = .inspect
    @State private var compareSelection: Set<UUID> = []
    @State private var isDropTargeted = false
    @State private var inspectedResults: [UUID: MediaInfoInspectionResult] = [:]
    @State private var inspectingIDs = Set<UUID>()
    @State private var metadataMode: MediaInfoMetadataMode = .general
    @State private var differencesOnly = false
    @State private var showMissingFields = false
    @State private var exportFeedback: String?

    private let inspector = MediaInfoInspector()
    private let comparisonService = MediaInfoComparisonService()
    private let primaryColumnWidth: CGFloat = 720
    private let sidebarWidth: CGFloat = 360
    private let workspaceSpacing: CGFloat = 24
    private let maxConcurrentInspections = 3

    private var workspaceWidth: CGFloat {
        primaryColumnWidth + sidebarWidth + workspaceSpacing
    }

    private var selectedItem: MediaInfoItem? {
        guard let selectedID else { return items.first }
        return items.first(where: { $0.id == selectedID }) ?? items.first
    }

    private var selectedInspectionState: MediaInfoInspectionState {
        state(for: selectedItem?.id)
    }

    private var compareItems: [MediaInfoItem] {
        items.filter { compareSelection.contains($0.id) }
    }

    private var compareReadyCount: Int {
        compareItems.filter { inspectedResults[$0.id] != nil }.count
    }

    private var compareTaskKey: String {
        compareItems.map(\.id.uuidString).joined(separator: "|")
    }

    private var headerStatusTitle: String {
        if presentationMode == .compare {
            if compareItems.count < 2 {
                return "Select 2+ Files"
            }
            if compareReadyCount < compareItems.count || compareItems.contains(where: { inspectingIDs.contains($0.id) }) {
                return "Preparing Comparison"
            }
            return differencesOnly ? "Differences Ready" : "Comparison Ready"
        }
        return selectedInspectionState.badgeTitle
    }

    private var headerStatusTint: Color {
        if presentationMode == .compare {
            if compareItems.count < 2 {
                return .orange
            }
            if compareReadyCount < compareItems.count || compareItems.contains(where: { inspectingIDs.contains($0.id) }) {
                return .blue
            }
            return .green
        }
        return selectedInspectionState.badgeTint
    }

    private var comparisonEntries: [MediaInfoComparisonEntry] {
        compareItems.compactMap { item in
            guard let result = inspectedResults[item.id] else { return nil }
            return MediaInfoComparisonEntry(
                id: item.id,
                title: item.name,
                subtitle: item.extensionLabel,
                sections: metadataSections(for: result, item: item)
            )
        }
    }

    private var comparisonSections: [MediaInfoComparisonSection] {
        comparisonService.build(
            entries: comparisonEntries,
            differencesOnly: differencesOnly,
            showMissingFields: showMissingFields
        )
    }

    private var filteredComparisonSections: [MediaInfoComparisonSection] {
        switch metadataMode {
        case .general:
            return comparisonSections.filter { $0.title == "General" }
        case .video:
            return comparisonSections.filter { $0.title == "Video" }
        case .audio:
            return comparisonSections.filter { $0.title == "Audio" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                workspaceSection
            }
            .frame(maxWidth: workspaceWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selectedItem?.id) {
            await inspectSelection()
        }
        .task(id: "\(presentationMode.rawValue)|\(compareTaskKey)") {
            await inspectCompareSelection()
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

            HStack(alignment: .center, spacing: 12) {
                Text("Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $presentationMode) {
                    ForEach(MediaInfoPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .frame(maxWidth: 360, alignment: .leading)

            HStack(spacing: 10) {
                MediaInfoBadge(title: "\(items.count) File\(items.count == 1 ? "" : "s")", tint: items.isEmpty ? .gray : .blue)
                MediaInfoBadge(
                    title: presentationMode == .compare
                        ? "\(compareItems.count) Comparing"
                        : (selectedItem == nil ? "No Selection" : "Summary Ready"),
                    tint: presentationMode == .compare
                        ? (compareItems.isEmpty ? .gray : (compareItems.count >= 2 ? .green : .orange))
                        : (selectedItem == nil ? .gray : .green)
                )
                MediaInfoBadge(title: headerStatusTitle, tint: headerStatusTint)
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: workspaceSpacing) {
                    VStack(alignment: .leading, spacing: 24) {
                        sourcePanel
                        selectionPanel
                    }
                    .frame(width: primaryColumnWidth, alignment: .topLeading)

                    summaryPanel
                        .frame(width: sidebarWidth, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 24) {
                    sourcePanel
                    selectionPanel
                    summaryPanel
                }
            }

            metadataPanel
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
                        compareSelection.removeAll()
                        inspectedResults.removeAll()
                        inspectingIDs.removeAll()
                        exportFeedback = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)
                    .help("Clear the current Media Info selection.")
                }
            }
        }
    }

    private var selectionPanel: some View {
        MediaInfoPanel(
            title: "Selection",
            headline: presentationMode == .compare ? "Compare candidates" : "Chosen files",
            subtitle: presentationMode == .compare
                ? "Pick two or more files to compare their metadata side by side."
                : "Review the files loaded into Media Info and switch the detail view."
        ) {
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
                VStack(alignment: .leading, spacing: 12) {
                    if presentationMode == .compare {
                        HStack(spacing: 10) {
                            MediaInfoBadge(
                                title: compareItems.count >= 2 ? "\(compareItems.count) Files Ready" : "\(compareItems.count) Selected",
                                tint: compareItems.count >= 2 ? .green : .orange
                            )
                            Text("Use the compare toggles on the right side of each file row.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

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

                                VStack(alignment: .trailing, spacing: 8) {
                                    Text(item.formattedFileSize)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    if presentationMode == .compare {
                                        Button {
                                            toggleCompareSelection(for: item.id)
                                        } label: {
                                            Label(
                                                compareSelection.contains(item.id) ? "Comparing" : "Compare",
                                                systemImage: compareSelection.contains(item.id) ? "checkmark.circle.fill" : "circle"
                                            )
                                            .font(.system(size: 12, weight: .semibold))
                                            .labelStyle(.titleAndIcon)
                                            .foregroundStyle(compareSelection.contains(item.id) ? Color.green : Color.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(compareSelection.contains(item.id) ? "Remove this file from the compare set." : "Add this file to the compare set.")
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(cardFill(for: item))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(cardStroke(for: item), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
            }
        }
    }

    private var summaryPanel: some View {
        MediaInfoPanel(
            title: presentationMode == .compare ? "Comparison" : "Summary",
            headline: presentationMode == .compare ? "Compare setup" : "Selected file",
            subtitle: presentationMode == .compare
                ? "Choose how the comparison table should surface matching and differing metadata."
                : "Basic filesystem metadata for the currently selected item."
        ) {
            if presentationMode == .compare {
                VStack(alignment: .leading, spacing: 12) {
                    MediaInfoRow(label: "Compared files", value: "\(compareItems.count)")
                    MediaInfoRow(label: "Loaded metadata", value: "\(comparisonEntries.count) / \(max(compareItems.count, 1))")

                    Toggle("Differences only", isOn: $differencesOnly)
                        .toggleStyle(.switch)
                        .help("Hide rows where every compared file has the same detected value.")

                    Toggle("Show missing fields", isOn: $showMissingFields)
                        .toggleStyle(.switch)
                        .help("Include rows where every compared file has no detected value.")

                    Text("Pick files with the compare control in the selection list. The lower inspector will switch to a side-by-side comparison table automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedItem {
                VStack(alignment: .leading, spacing: 12) {
                    MediaInfoRow(label: "Name", value: selectedItem.name)
                    MediaInfoRow(label: "Path", value: selectedItem.url.path, monospace: true)
                    MediaInfoRow(label: "Type", value: selectedItem.kind.displayName)
                    MediaInfoRow(label: "Extension", value: selectedItem.extensionLabel)
                    MediaInfoRow(label: "Size", value: selectedItem.formattedFileSize)
                    MediaInfoRow(label: "Created", value: selectedItem.createdAt)
                    MediaInfoRow(label: "Modified", value: selectedItem.modifiedAt)

                    HStack(spacing: 10) {
                        Button("Export TXT", action: exportMetadataReport)
                            .buttonStyle(.borderedProminent)
                            .disabled(!canExportMetadata)
                            .help("Save the current metadata inspector as a plain-text report.")
                    }

                    if let exportFeedback {
                        Text(exportFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                MediaInfoEmptyState(message: "Select a file to view its summary.")
            }
        }
    }

    private var metadataPanel: some View {
        MediaInfoPanel(title: "Metadata", headline: "Media attributes", subtitle: "Use the inspector below to review general, video, and audio stream details without squeezing technical metadata into the right sidebar.") {
            if presentationMode == .compare {
                compareMetadataContent
            } else {
                inspectMetadataContent
            }
        }
    }

    @ViewBuilder
    private var inspectMetadataContent: some View {
        switch selectedInspectionState {
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
                    let sections = filteredMetadataSections(for: metadata, item: selectedItem, mode: metadataMode)

                    metadataModePicker

                    if sections.isEmpty {
                        MediaInfoEmptyState(message: metadataMode.emptyMessage)
                    }

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

    @ViewBuilder
    private var compareMetadataContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataModePicker

            if compareItems.count < 2 {
                MediaInfoEmptyState(message: "Select two or more files in the list above to compare their metadata.")
            } else if compareReadyCount < compareItems.count || compareItems.contains(where: { inspectingIDs.contains($0.id) }) {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing comparison metadata...")
                        .font(.headline.weight(.semibold))
                    Text("AssetFox is loading metadata for the selected compare set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if filteredComparisonSections.isEmpty {
                MediaInfoEmptyState(message: differencesOnly ? "No differences were found for the current compare set." : "No comparable metadata rows are available for the current selection.")
            } else {
                ForEach(filteredComparisonSections) { section in
                    MediaInfoComparisonSectionView(section: section, emphasizeDifferences: differencesOnly)
                }
            }
        }
    }

    private var metadataModePicker: some View {
        Picker("Metadata Section", selection: $metadataMode) {
            ForEach(MediaInfoMetadataMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 4)
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
        compareSelection.formIntersection(Set(items.map(\.id)))
    }

    @MainActor
    private func inspectSelection() async {
        guard let selectedItem else { return }
        await ensureInspection(for: [selectedItem])
    }

    @MainActor
    private func inspectCompareSelection() async {
        guard presentationMode == .compare, !compareItems.isEmpty else { return }
        await ensureInspection(for: compareItems)
    }

    @MainActor
    private func ensureInspection(for itemsToInspect: [MediaInfoItem]) async {
        let pendingItems = itemsToInspect.filter { inspectedResults[$0.id] == nil && !inspectingIDs.contains($0.id) }
        guard !pendingItems.isEmpty else { return }

        pendingItems.forEach { inspectingIDs.insert($0.id) }

        var batchStart = 0
        while batchStart < pendingItems.count {
            let batchEnd = min(batchStart + maxConcurrentInspections, pendingItems.count)
            let batch = Array(pendingItems[batchStart..<batchEnd])

            await withTaskGroup(of: (UUID, MediaInfoInspectionResult).self) { group in
                for item in batch {
                    group.addTask {
                        (item.id, await inspector.inspect(url: item.url))
                    }
                }

                for await (id, result) in group {
                    inspectedResults[id] = result
                    inspectingIDs.remove(id)
                }
            }

            batchStart = batchEnd
        }
    }

    private func state(for id: UUID?) -> MediaInfoInspectionState {
        guard let id else { return .idle }
        if let result = inspectedResults[id] {
            return .loaded(result)
        }
        if inspectingIDs.contains(id) {
            return .loading
        }
        return .idle
    }

    private func toggleCompareSelection(for id: UUID) {
        if compareSelection.contains(id) {
            compareSelection.remove(id)
        } else {
            compareSelection.insert(id)
        }
    }

    private func cardFill(for item: MediaInfoItem) -> Color {
        if item.id == selectedID {
            return Color.accentColor.opacity(0.12)
        }
        if presentationMode == .compare && compareSelection.contains(item.id) {
            return Color.green.opacity(0.10)
        }
        return Color.white.opacity(0.03)
    }

    private func cardStroke(for item: MediaInfoItem) -> Color {
        if item.id == selectedID {
            return Color.accentColor.opacity(0.35)
        }
        if presentationMode == .compare && compareSelection.contains(item.id) {
            return Color.green.opacity(0.28)
        }
        return Color.white.opacity(0.04)
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
                        .optional("Format version", deepMetadata.general.formatVersion),
                        .optional("Format profile", deepMetadata.general.formatProfile),
                        .optional("Format settings", deepMetadata.general.formatSettings),
                        .optional("Codec ID", deepMetadata.general.codecID),
                        .required("File size", deepMetadata.general.fileSize ?? item?.formattedFileSize),
                        .required("Duration", deepMetadata.general.duration ?? metadata.duration),
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
                        .optional("Bit rate", track.bitRate),
                        .required("Width", track.widthDisplay ?? track.width.map { "\($0) pixels" }),
                        .required("Height", track.heightDisplay ?? track.height.map { "\($0) pixels" }),
                        .optional("Display aspect ratio", displayAspectRatioValue(for: track)),
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

    private func filteredMetadataSections(for metadata: MediaInfoInspectionResult, item: MediaInfoItem?, mode: MediaInfoMetadataMode) -> [MediaInfoInspectorSection] {
        let sections = metadataSections(for: metadata, item: item)
        switch mode {
        case .general:
            return sections.filter { $0.title == "General" }
        case .video:
            return sections.filter { $0.title == "Video" }
        case .audio:
            return sections.filter { $0.title == "Audio" }
        }
    }

    private var canExportMetadata: Bool {
        selectedItem != nil && currentExportSections != nil
    }

    private var currentExportSections: [MediaInfoInspectorSection]? {
        guard case .loaded(let metadata) = selectedInspectionState else { return nil }
        return metadataSections(for: metadata, item: selectedItem)
    }

    private func exportMetadataReport() {
        guard let selectedItem,
              let sections = currentExportSections else { return }

        let panel = NSSavePanel()
        panel.title = "Export Media Info Report"
        panel.nameFieldStringValue = selectedItem.url.deletingPathExtension().lastPathComponent + "-metadata.txt"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let report = buildMetadataReport(for: selectedItem, sections: sections)
            try report.write(to: destinationURL, atomically: true, encoding: .utf8)
            exportFeedback = "Saved metadata report to \(destinationURL.lastPathComponent)"
        } catch {
            exportFeedback = "Could not save metadata report: \(error.localizedDescription)"
        }
    }

    private func buildMetadataReport(for item: MediaInfoItem, sections: [MediaInfoInspectorSection]) -> String {
        var lines: [String] = []
        lines.append("AssetFox Media Info Report")
        lines.append("")
        lines.append("File")
        lines.append("Name: \(item.name)")
        lines.append("Path: \(item.url.path)")
        lines.append("Type: \(item.kind.displayName)")
        lines.append("Extension: \(item.extensionLabel)")
        lines.append("Size: \(item.formattedFileSize)")
        lines.append("Created: \(item.createdAt)")
        lines.append("Modified: \(item.modifiedAt)")
        lines.append("")

        for section in sections {
            let header = section.subtitle.map { "\(section.title) \($0)" } ?? section.title
            lines.append(header)
            lines.append(String(repeating: "-", count: header.count))
            for row in section.rows {
                lines.append("\(row.label): \(row.value)")
            }
            lines.append("")
        }

        if case .loaded(let metadata) = selectedInspectionState, !metadata.warnings.isEmpty {
            lines.append("Warnings")
            lines.append("--------")
            lines.append(contentsOf: metadata.warnings)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func displayAspectRatioValue(for track: MediaInfoVideoTrackMetadata) -> String? {
        let rawValue = track.displayAspectRatio?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratioValue = parseAspectRatioValue(rawValue) ?? {
            guard let width = track.width, let height = track.height, width > 0, height > 0 else { return nil }
            return Double(width) / Double(height)
        }()

        guard let ratioValue else { return rawValue }

        let normalizedRawValue = rawValue.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let familiar = closestAspectRatioLabel(for: ratioValue)

        if let normalizedRawValue,
           !normalizedRawValue.localizedCaseInsensitiveContains(familiar) {
            return "\(normalizedRawValue) (\(familiar))"
        }

        if let normalizedRawValue {
            return normalizedRawValue
        }

        return String(format: "%.3f (%@)", ratioValue, familiar)
    }

    private func parseAspectRatioValue(_ value: String?) -> Double? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        if let numeric = Double(value), numeric > 0 {
            return numeric
        }

        if value.contains(":") {
            let parts = value.split(separator: ":")
            if parts.count == 2,
               let width = Double(parts[0]),
               let height = Double(parts[1]),
               height != 0 {
                return width / height
            }
        }

        return nil
    }

    private func closestAspectRatioLabel(for value: Double) -> String {
        let knownRatios: [(label: String, value: Double)] = [
            ("1:1", 1.0),
            ("5:4", 1.25),
            ("4:3", 4.0 / 3.0),
            ("3:2", 1.5),
            ("14:9", 14.0 / 9.0),
            ("16:10", 1.6),
            ("5:3", 5.0 / 3.0),
            ("16:9", 16.0 / 9.0),
            ("17:9", 17.0 / 9.0),
            ("2:1", 2.0),
            ("2.39:1", 2.39),
            ("2.40:1", 2.4),
            ("9:16", 9.0 / 16.0),
            ("4:5", 4.0 / 5.0),
            ("3:4", 3.0 / 4.0)
        ]

        return knownRatios
            .min(by: { abs($0.value - value) < abs($1.value - value) })?
            .label ?? String(format: "%.3f:1", value)
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

private enum MediaInfoPresentationMode: String, CaseIterable, Identifiable {
    case inspect
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inspect:
            return "Inspect"
        case .compare:
            return "Compare"
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

private struct MediaInfoInspectorSectionView: View {
    let section: MediaInfoInspectorSection

    private var visibleRows: [MediaInfoInspectorField] {
        section.rows.filter { $0.alwaysShow || !$0.isPlaceholder }
    }

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
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
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

                    if index < visibleRows.count - 1 {
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

private struct MediaInfoComparisonSectionView: View {
    let section: MediaInfoComparisonSection
    var emphasizeDifferences = false

    private let fieldColumnWidth: CGFloat = 160
    private let valueColumnWidth: CGFloat = 220
    private let minimumFlexibleValueColumnWidth: CGFloat = 210
    private let differenceTint = Color(red: 0.62, green: 0.53, blue: 0.22)

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

            Group {
                if usesFlexibleColumns {
                    VStack(spacing: 0) {
                        if let firstRow = section.rows.first {
                            comparisonHeaderRow(firstRow: firstRow, flexibleColumns: true)
                                .background(Color.white.opacity(0.03))
                        }

                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            comparisonValueRow(row: row, index: index, flexibleColumns: true)

                            if index < section.rows.count - 1 {
                                Divider()
                                    .overlay(Color.white.opacity(0.04))
                            }
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            if let firstRow = section.rows.first {
                                comparisonHeaderRow(firstRow: firstRow, flexibleColumns: false)
                                    .background(Color.white.opacity(0.03))
                            }

                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                comparisonValueRow(row: row, index: index, flexibleColumns: false)

                                if index < section.rows.count - 1 {
                                    Divider()
                                        .overlay(Color.white.opacity(0.04))
                                }
                            }
                        }
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

    private var usesFlexibleColumns: Bool {
        guard let firstRow = section.rows.first else { return true }
        return firstRow.values.count <= 3
    }

    @ViewBuilder
    private func comparisonHeaderRow(firstRow: MediaInfoComparisonRow, flexibleColumns: Bool) -> some View {
        HStack(spacing: 0) {
            Text("Field")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.secondary)
                .frame(width: fieldColumnWidth, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            ForEach(firstRow.values) { value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if let subtitle = value.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .comparisonValueColumnLayout(flexible: flexibleColumns, fixedWidth: valueColumnWidth, minimumWidth: minimumFlexibleValueColumnWidth)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func comparisonValueRow(row: MediaInfoComparisonRow, index: Int, flexibleColumns: Bool) -> some View {
        HStack(spacing: 0) {
            Text(row.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: fieldColumnWidth, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            ForEach(row.values) { value in
                Text(value.value)
                    .font(.system(size: 13, weight: .semibold, design: value.monospace ? .monospaced : .default))
                    .foregroundStyle(value.isPlaceholder ? .secondary : .primary)
                    .comparisonValueColumnLayout(flexible: flexibleColumns, fixedWidth: valueColumnWidth, minimumWidth: minimumFlexibleValueColumnWidth)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
            }
        }
        .background(comparisonRowBackground(index: index, highlighted: row.hasDifferences))
    }

    private func comparisonRowBackground(index: Int, highlighted: Bool) -> Color {
        if highlighted {
            let baseOpacity = emphasizeDifferences ? (index.isMultiple(of: 2) ? 0.30 : 0.26) : (index.isMultiple(of: 2) ? 0.18 : 0.14)
            return differenceTint.opacity(baseOpacity)
        }
        return index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension View {
    @ViewBuilder
    func comparisonValueColumnLayout(flexible: Bool, fixedWidth: CGFloat, minimumWidth: CGFloat) -> some View {
        if flexible {
            self
                .frame(maxWidth: .infinity, minHeight: 1, alignment: .leading)
                .frame(minWidth: minimumWidth, alignment: .leading)
        } else {
            self
                .frame(width: fixedWidth, alignment: .leading)
        }
    }
}
