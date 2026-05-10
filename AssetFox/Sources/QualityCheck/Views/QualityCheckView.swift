import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct QualityCheckView: View {
    @State private var viewModel = QualityCheckViewModel()
    @State private var isDropTargeted = false
    @State private var showRawOutput = false
    @State private var viewerLayoutMode = QualityCheckViewerLayoutMode.fitAll

    private let primaryColumnWidth = AssetFoxDesign.primaryColumnWidth
    private let sidebarWidth = AssetFoxDesign.sidebarWidth
    private let workspaceSpacing = AssetFoxDesign.workspaceSpacing
    private let wideModeExtraWidth: CGFloat = 240

    private var workspaceWidth: CGFloat {
        primaryColumnWidth + sidebarWidth + workspaceSpacing
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = contentWidth(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    workspace(contentWidth: contentWidth)
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, AssetFoxDesign.pageHorizontalPadding)
                .padding(.vertical, AssetFoxDesign.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: contentAlignment(for: proxy.size.width))
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("Quality Check", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background(
            QualityCheckKeyboardShortcutHost(
                onTogglePlayback: {
                    viewModel.togglePlayback()
                },
                onStepBackward: {
                    viewModel.stepBackward()
                },
                onStepForward: {
                    viewModel.stepForward()
                }
            )
            .frame(width: 0, height: 0)
        )
    }

    private var header: some View {
        AssetFoxPageHeader(
            title: "Quality Check",
            systemImage: "rectangle.split.3x1",
            subtitle: "Compare multiple export versions with synchronized playback and automated black, freeze, and cut-point checks."
        ) {
            HStack(spacing: 10) {
                badge(viewModel.selectedCountLabel, tint: viewModel.items.isEmpty ? .secondary : .accentColor)
                badge(viewModel.runtimeSnapshot.ffmpeg.isAvailable ? "ffmpeg Ready" : "ffmpeg Missing", tint: viewModel.runtimeSnapshot.ffmpeg.isAvailable ? .green : .orange)
                badge(viewModel.analysisStatus, tint: viewModel.isAnalyzing ? .blue : .secondary)
            }
        }
    }

    private func contentWidth(for viewportWidth: CGFloat) -> CGFloat {
        let availableWidth = max(320, viewportWidth - AssetFoxDesign.pageHorizontalPadding * 2)
        guard availableWidth >= workspaceWidth + wideModeExtraWidth else {
            return min(workspaceWidth, availableWidth)
        }
        return availableWidth
    }

    private func contentAlignment(for viewportWidth: CGFloat) -> Alignment {
        let availableWidth = max(320, viewportWidth - AssetFoxDesign.pageHorizontalPadding * 2)
        return availableWidth >= workspaceWidth + wideModeExtraWidth ? .leading : .center
    }

    @ViewBuilder
    private func workspace(contentWidth: CGFloat) -> some View {
        if contentWidth >= workspaceWidth + wideModeExtraWidth {
            wideWorkspace(contentWidth: contentWidth)
        } else {
            compactWorkspace
        }
    }

    private func wideWorkspace(contentWidth: CGFloat) -> some View {
        let mainColumnWidth = max(primaryColumnWidth, contentWidth - sidebarWidth - workspaceSpacing)

        return HStack(alignment: .top, spacing: workspaceSpacing) {
            VStack(alignment: .leading, spacing: 24) {
                wideViewerPanel(viewerWidth: mainColumnWidth)
                if viewModel.isAnalyzing || !viewModel.findings.isEmpty {
                    findingsPanel
                }
            }
            .frame(width: mainColumnWidth, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 24) {
                metadataPanel
                analysisPanel
                if !viewModel.isAnalyzing && viewModel.findings.isEmpty {
                    wideFindingsStatusPanel
                }
                rawOutputPanel
            }
            .frame(width: sidebarWidth, alignment: .topLeading)
        }
    }

    private var compactWorkspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: workspaceSpacing) {
                VStack(alignment: .leading, spacing: 24) {
                    sourcePanel
                    viewerPanel(viewerWidth: primaryColumnWidth)
                    findingsPanel
                }
                .frame(width: primaryColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 24) {
                    metadataPanel
                    analysisPanel
                    rawOutputPanel
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 24) {
                sourcePanel
                viewerPanel(viewerWidth: primaryColumnWidth)
                metadataPanel
                analysisPanel
                findingsPanel
                rawOutputPanel
            }
        }
    }

    private var sourcePanel: some View {
        sectionCard(eyebrow: "Source", title: "Export versions", body: "Load two or more video exports for synchronized review.") {
            RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                )
                .frame(height: 126)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                        Text("Drop export files here")
                            .font(.headline.weight(.semibold))
                        Text("MOV, MP4, MXF, and other AVFoundation-readable video files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))

            HStack(spacing: 10) {
                Button("Choose Videos") {
                    viewModel.chooseVideos()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    viewModel.clear()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.items.isEmpty)
            }
        }
    }

    private func wideViewerPanel(viewerWidth: CGFloat) -> some View {
        sectionCard(eyebrow: "Viewer", title: "Synchronized playback", body: "Load exports, compare versions, and step through the shared timeline frame by frame.") {
            if viewModel.items.isEmpty {
                wideViewerEmptyState
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Label("\(viewModel.items.count) exports loaded", systemImage: "film.stack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let referenceItem = viewModel.manualReferenceItem {
                        Label("Reference: \(referenceItem.name)", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Label("Choose a reference to switch layout", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    viewerLayoutPicker

                    Button("Add Videos") {
                        viewModel.chooseVideos()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear") {
                        viewModel.clear()
                    }
                    .buttonStyle(.bordered)
                }

                videoBrowser(viewerWidth: viewerWidth)

                playbackControls
            }
        }
    }

    private var wideViewerEmptyState: some View {
        RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
            .fill(isDropTargeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [9, 9]))
            )
            .frame(minHeight: 260)
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

                    VStack(spacing: 6) {
                        Text("Load export versions")
                            .font(.title3.weight(.semibold))
                        Text("Drop multiple video files here, or choose them from disk.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("Choose Videos") {
                            viewModel.chooseVideos()
                        }
                        .buttonStyle(.borderedProminent)

                        Text("MOV, MP4, MXF, and other AVFoundation-readable files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    private var wideFindingsStatusPanel: some View {
        sectionCard(eyebrow: "Findings", title: "QC results", body: "Run analysis to populate timeline findings.") {
            emptyState("No findings yet.", detail: "Results will appear below the viewer when analysis finds issues.")
        }
    }

    private func viewerPanel(viewerWidth: CGFloat) -> some View {
        sectionCard(eyebrow: "Viewer", title: "Synchronized playback", body: "Review all loaded exports against a shared playhead.") {
            if viewModel.items.isEmpty {
                emptyState("No videos loaded yet.", detail: "Choose or drop export files to enable playback.")
            } else {
                viewerLayoutPicker

                videoBrowser(viewerWidth: viewerWidth)

                playbackControls
            }
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(viewModel.currentFrame) },
                    set: { viewModel.seekAll(toFrame: Int($0.rounded())) }
                ),
                in: 0...max(Double(viewModel.totalFrames), 1),
                step: 1
            )

            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                .help("Play or pause all videos. Shortcut: Space.")

                Button {
                    viewModel.stepBackward()
                } label: {
                    Label("Previous Frame", systemImage: "backward.frame.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(viewModel.currentFrame <= 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Step back one frame.")

                Button {
                    viewModel.stepForward()
                } label: {
                    Label("Next Frame", systemImage: "forward.frame.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(viewModel.currentFrame >= viewModel.totalFrames)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Step forward one frame.")

                Button {
                    viewModel.toggleAudioMuted()
                } label: {
                    Label(viewModel.isAudioMuted ? "Unmute" : "Mute", systemImage: viewModel.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(viewModel.items.isEmpty)
                .help(viewModel.isAudioMuted ? "Restore reference audio." : "Mute reference audio.")

                Text("\(viewModel.currentFrameTimecode) / \(viewModel.totalFrameTimecode)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Frame \(viewModel.currentFrame) / \(viewModel.totalFrames)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    private var metadataPanel: some View {
        sectionCard(eyebrow: "Selection", title: "Loaded videos", body: "Metadata from AVFoundation for the current QC set.") {
            if viewModel.items.isEmpty {
                emptyState("No selection.", detail: "Metadata appears after videos are loaded.")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.items) { item in
                        Button {
                            viewModel.selectedItemID = item.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    if item.id == viewModel.manualReferenceItem?.id {
                                        Text("Reference")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.16))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    }
                                    Text(item.aspectRatioLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(item.resolutionLabel) • \(item.formattedFrameRate) • \(item.formattedDuration)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                                    .fill(item.id == viewModel.selectedItem?.id ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var analysisPanel: some View {
        sectionCard(eyebrow: "Analysis", title: "Automated checks", body: "Run FFmpeg-backed black, freeze, and cut-point checks without blocking playback.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Tolerance")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.toleranceFrames) frames")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.toleranceFrames) },
                        set: { viewModel.toleranceFrames = max(1, Int($0.rounded())) }
                    ),
                    in: 1...12,
                    step: 1
                )
                    .disabled(viewModel.isAnalyzing)

                Text("Reference: \(viewModel.referenceFrameRateLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.analyze()
                } label: {
                    Label("Analyze", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.items.isEmpty || viewModel.isAnalyzing)

                if viewModel.isAnalyzing {
                    ProgressView()
                    Button("Cancel Analysis") {
                        viewModel.cancelAnalysis()
                    }
                    .buttonStyle(.bordered)
                }

                runtimeLine(viewModel.runtimeSnapshot.ffmpeg)
                runtimeLine(viewModel.runtimeSnapshot.ffprobe)
            }
        }
    }

    private var findingsPanel: some View {
        sectionCard(eyebrow: "Findings", title: "QC results", body: "Issues are grouped by severity, file, and timeline position.") {
            if viewModel.findings.isEmpty {
                emptyState(viewModel.isAnalyzing ? "Analysis running." : "No findings yet.", detail: viewModel.isAnalyzing ? viewModel.analysisStatus : "Run Analyze after loading videos.")
            } else {
                VStack(spacing: 0) {
                    findingHeader
                    ForEach(viewModel.findings) { finding in
                        findingRow(finding)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    private var rawOutputPanel: some View {
        sectionCard(eyebrow: "Diagnostics", title: "Raw analyzer output", body: "Keep parsed FFmpeg details available for troubleshooting.") {
            DisclosureGroup(isExpanded: $showRawOutput) {
                if viewModel.rawOutputs.isEmpty {
                    emptyState("No raw output.", detail: "Raw FFmpeg output appears after analysis.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.rawOutputs) { output in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(output.fileName)
                                        .font(.caption.weight(.semibold))
                                    Text(output.rawOutput.isEmpty ? "No output." : output.rawOutput)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 280)
                }
            } label: {
                Label("Show raw output", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var viewerLayoutPicker: some View {
        Picker("Viewer Layout", selection: $viewerLayoutMode) {
            ForEach(QualityCheckViewerLayoutMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 152)
        .labelsHidden()
        .help("Fit All keeps loaded videos visible. Large keeps the larger horizontal review strip.")
    }

    @ViewBuilder
    private func videoBrowser(viewerWidth: CGFloat) -> some View {
        switch viewerLayoutMode {
        case .fitAll:
            if viewModel.hasManualReference {
                videoReferenceLayout(viewerWidth: viewerWidth)
            } else {
                videoOverviewRow(viewerWidth: viewerWidth)
            }
        case .large:
            videoStrip(viewerWidth: viewerWidth)
        }
    }

    private func videoOverviewRow(viewerWidth: CGFloat) -> some View {
        let items = viewModel.items
        let tileWidth = overviewTileWidth(viewerWidth: viewerWidth)
        let previewHeight = overviewPreviewHeight(tileWidth: tileWidth)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Select Set Reference to open the focused comparison layout.", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    videoTile(item, previewHeight: previewHeight, fixedTileWidth: tileWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func videoReferenceLayout(viewerWidth: CGFloat) -> some View {
        let reference = viewModel.manualReferenceItem ?? viewModel.referenceItem
        let comparisonItems = viewModel.items.filter { $0.id != reference?.id }
        let layout = referenceLayoutMetrics(viewerWidth: viewerWidth, comparisonCount: comparisonItems.count)

        return HStack(alignment: .top, spacing: 12) {
            if let reference {
                videoTile(
                    reference,
                    previewHeight: referencePreviewHeight(for: reference, tileWidth: layout.referenceTileWidth),
                    fixedTileWidth: layout.referenceTileWidth
                )
            }

            LazyVGrid(columns: layout.comparisonColumns, alignment: .leading, spacing: 12) {
                ForEach(comparisonItems) { item in
                    videoTile(
                        item,
                        previewHeight: comparisonPreviewHeight(for: item, tileWidth: layout.comparisonTileWidth),
                        fixedTileWidth: layout.comparisonTileWidth
                    )
                }
            }
            .frame(width: layout.comparisonColumnWidth, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func videoStrip(viewerWidth: CGFloat) -> some View {
        let previewHeight = videoPreviewHeight(for: viewerWidth)

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(viewModel.items) { item in
                    videoTile(item, previewHeight: previewHeight)
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.visible)
    }

    private func videoPreviewHeight(for viewerWidth: CGFloat) -> CGFloat {
        let availableGridWidth = max(320, viewerWidth - AssetFoxDesign.panelPadding * 2)
        return min(max(availableGridWidth * 0.28, 340), 560)
    }

    private func overviewTileWidth(viewerWidth: CGFloat) -> CGFloat {
        let count = max(viewModel.items.count, 1)
        let availableWidth = max(260, viewerWidth - AssetFoxDesign.panelPadding * 2)
        let totalSpacing = CGFloat(max(count - 1, 0)) * 12
        return max(132, floor((availableWidth - totalSpacing) / CGFloat(count)))
    }

    private func overviewPreviewHeight(tileWidth: CGFloat) -> CGFloat {
        min(max((tileWidth - 24) * 0.68, 118), 260)
    }

    private func referenceLayoutMetrics(viewerWidth: CGFloat, comparisonCount: Int) -> ReferenceLayoutMetrics {
        let availableWidth = max(620, viewerWidth - AssetFoxDesign.panelPadding * 2)
        let referenceTileWidth = min(max(availableWidth * 0.54, 420), availableWidth * 0.64)
        let comparisonColumnWidth = max(220, availableWidth - referenceTileWidth - 12)
        let columnCount = comparisonColumnWidth >= 500 && comparisonCount > 1 ? 2 : 1
        let comparisonSpacing = CGFloat(max(columnCount - 1, 0)) * 12
        let comparisonTileWidth = max(180, floor((comparisonColumnWidth - comparisonSpacing) / CGFloat(columnCount)))
        let columns = Array(
            repeating: GridItem(.fixed(comparisonTileWidth), spacing: 12, alignment: .top),
            count: columnCount
        )

        return ReferenceLayoutMetrics(
            referenceTileWidth: referenceTileWidth,
            comparisonColumnWidth: comparisonColumnWidth,
            comparisonTileWidth: comparisonTileWidth,
            comparisonColumns: columns
        )
    }

    private func referencePreviewHeight(for item: QualityCheckVideoItem, tileWidth: CGFloat) -> CGFloat {
        let previewWidth = max(120, tileWidth - 24)
        return min(max(previewWidth / max(item.aspectRatioValue, 0.45), 300), 560)
    }

    private func comparisonPreviewHeight(for item: QualityCheckVideoItem, tileWidth: CGFloat) -> CGFloat {
        let previewWidth = max(120, tileWidth - 24)
        return min(max(previewWidth / max(item.aspectRatioValue, 0.45), 120), 250)
    }

    private func videoTileWidth(for item: QualityCheckVideoItem, previewHeight: CGFloat, minimumPreviewWidth: CGFloat = 260) -> CGFloat {
        let previewWidth = previewWidth(for: item, previewHeight: previewHeight, minimumWidth: minimumPreviewWidth)
        return previewWidth + 24
    }

    private func previewWidth(for item: QualityCheckVideoItem, previewHeight: CGFloat, minimumWidth: CGFloat = 260) -> CGFloat {
        min(max(previewHeight * item.aspectRatioValue, minimumWidth), 980)
    }

    private var findingHeader: some View {
        HStack {
            tableText("Severity", width: 70)
            tableText("File", width: 150)
            tableText("Frame", width: 92)
            tableText("Duration", width: 78)
            Text("Message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func videoTile(_ item: QualityCheckVideoItem, previewHeight: CGFloat, minimumPreviewWidth: CGFloat = 260, fixedTileWidth: CGFloat? = nil) -> some View {
        let isReference = item.id == viewModel.manualReferenceItem?.id
        let tileWidth = fixedTileWidth ?? videoTileWidth(for: item, previewHeight: previewHeight, minimumPreviewWidth: minimumPreviewWidth)
        let previewWidth = fixedTileWidth.map { max(80, $0 - 24) } ?? previewWidth(for: item, previewHeight: previewHeight, minimumWidth: minimumPreviewWidth)

        return VStack(alignment: .leading, spacing: 10) {
            QualityCheckPlayerView(
                player: viewModel.player(for: item),
                onTogglePlayback: {
                    viewModel.togglePlayback()
                },
                onStepBackward: {
                    viewModel.stepBackward()
                },
                onStepForward: {
                    viewModel.stepForward()
                }
            )
                .frame(width: previewWidth, height: previewHeight)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(item.resolutionLabel) • \(item.aspectRatioLabel) • \(item.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    viewModel.setReference(item)
                } label: {
                    Label(isReference ? "Reference" : "Set Reference", systemImage: isReference ? "checkmark.seal.fill" : "scope")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isReference ? .green : .accentColor)
                .help(isReference ? "This video is the reference for cut-point comparison." : "Use this video as the comparison reference.")

                Button {
                    viewModel.remove(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove this video from Quality Check.")
            }
        }
        .padding(12)
        .frame(width: tileWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                .fill(isReference ? Color.green.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AssetFoxDesign.innerRadius, style: .continuous)
                .strokeBorder(isReference ? Color.green.opacity(0.65) : Color.secondary.opacity(0.10), lineWidth: isReference ? 1.5 : 1)
        )
    }

    private func findingRow(_ finding: QualityCheckFinding) -> some View {
        Button {
            viewModel.seek(to: finding)
        } label: {
            HStack(alignment: .top) {
                tableText(finding.severity.rawValue, width: 70, color: severityColor(finding.severity))
                tableText(finding.fileName, width: 150)
                tableText(QualityCheckFormatting.formatFrameTimecode(finding.timeSeconds, frameRate: viewModel.frameRate(for: finding)), width: 92)
                tableText(finding.durationSeconds.map { QualityCheckFormatting.formatFrameDuration($0, frameRate: viewModel.frameRate(for: finding)) } ?? "-", width: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.message)
                        .font(.caption.weight(.semibold))
                    if let details = finding.details {
                        Text(details)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump playback to this finding.")
    }

    private func runtimeLine(_ resolution: RuntimeToolResolution) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(resolution.tool.rawValue)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(resolution.source.rawValue)
                    .font(.caption)
                    .foregroundStyle(resolution.isAvailable ? .green : .orange)
            }
            Text(resolution.displayPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func sectionCard<Content: View>(eyebrow: String, title: String, body: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(AssetFoxDesign.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AssetFoxPanelBackground())
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func tableText(_ text: String, width: CGFloat, color: Color = .primary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: .leading)
    }

    private func severityColor(_ severity: QualityCheckSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .secondary
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    viewModel.add(urls: [url])
                }
            }
            accepted = true
        }

        return accepted
    }
}

private enum QualityCheckViewerLayoutMode: String, CaseIterable, Identifiable {
    case fitAll = "Fit All"
    case large = "Large"

    var id: Self { self }
}

private struct ReferenceLayoutMetrics {
    let referenceTileWidth: CGFloat
    let comparisonColumnWidth: CGFloat
    let comparisonTileWidth: CGFloat
    let comparisonColumns: [GridItem]
}

private struct QualityCheckPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onTogglePlayback: () -> Void
    let onStepBackward: () -> Void
    let onStepForward: () -> Void

    func makeNSView(context: Context) -> KeyboardControlledPlayerView {
        let view = KeyboardControlledPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        view.onTogglePlayback = onTogglePlayback
        view.onStepBackward = onStepBackward
        view.onStepForward = onStepForward
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: KeyboardControlledPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.onTogglePlayback = onTogglePlayback
        nsView.onStepBackward = onStepBackward
        nsView.onStepForward = onStepForward
        nsView.controlsStyle = .none
        nsView.videoGravity = .resizeAspect
    }
}

private struct QualityCheckKeyboardShortcutHost: NSViewRepresentable {
    let onTogglePlayback: () -> Void
    let onStepBackward: () -> Void
    let onStepForward: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(
            onTogglePlayback: onTogglePlayback,
            onStepBackward: onStepBackward,
            onStepForward: onStepForward
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTogglePlayback = onTogglePlayback
        context.coordinator.onStepBackward = onStepBackward
        context.coordinator.onStepForward = onStepForward
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onTogglePlayback: (() -> Void)?
        var onStepBackward: (() -> Void)?
        var onStepForward: (() -> Void)?

        private var monitor: Any?

        func install(
            onTogglePlayback: @escaping () -> Void,
            onStepBackward: @escaping () -> Void,
            onStepForward: @escaping () -> Void
        ) {
            self.onTogglePlayback = onTogglePlayback
            self.onStepBackward = onStepBackward
            self.onStepForward = onStepForward

            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard relevantModifiers.isEmpty else { return false }

            switch event.keyCode {
            case 49:
                onTogglePlayback?()
                return true
            case 123:
                onStepBackward?()
                return true
            case 124:
                onStepForward?()
                return true
            default:
                return false
            }
        }
    }
}

private final class KeyboardControlledPlayerView: AVPlayerView {
    var onTogglePlayback: (() -> Void)?
    var onStepBackward: (() -> Void)?
    var onStepForward: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard relevantModifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 49:
            onTogglePlayback?()
        case 123:
            onStepBackward?()
        case 124:
            onStepForward?()
        default:
            super.keyDown(with: event)
        }
    }
}
