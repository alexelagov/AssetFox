import SwiftUI

struct CollectMediaView: View {
    @State private var viewModel = CollectMediaViewModel()
    @State private var showAdvancedOptions = false
    @State private var showFullLog = false

    private let primaryColumnWidth: CGFloat = 720
    private let sidebarWidth: CGFloat = 360
    private let workspaceSpacing: CGFloat = 24

    private var workspaceWidth: CGFloat {
        primaryColumnWidth + sidebarWidth + workspaceSpacing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topSection
                workspaceSection
            }
            .frame(maxWidth: workspaceWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.snappy(duration: 0.28), value: viewModel.isCollecting)
        .animation(.easeInOut(duration: 0.22), value: showAdvancedOptions)
        .animation(.easeInOut(duration: 0.22), value: showFullLog)
        .sheet(isPresented: Binding(
            get: { viewModel.summary != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSummary()
                }
            }
        )) {
            if let result = viewModel.summary {
                CollectMediaSummaryView(
                    result: result,
                    onOpenDestination: { viewModel.openDestination(result) },
                    onRevealReport: { viewModel.revealReport(result) },
                    onRevealMissing: { viewModel.revealMissing(result) }
                )
            }
        }
        .alert("Collect Media", isPresented: Binding(
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
    }

    private var topSection: some View {
        headerBlock
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Collect Media", systemImage: "shippingbox")
                .font(.system(size: 28, weight: .semibold))

            Text("Collect the media referenced by a Premiere FCP XML into one clean destination, with optional relink assistance and audit reports.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 700, alignment: .leading)

            HStack(spacing: 10) {
                statusBadge
                capabilityBadge(
                    title: viewModel.ffProbeAvailable ? "ffprobe Ready" : "ffprobe Unavailable",
                    tone: viewModel.ffProbeAvailable ? .neutral : .warning
                )
                capabilityBadge(
                    title: viewModel.options.searchRoot == nil ? "Search Root Optional" : "Search Root Set",
                    tone: viewModel.options.searchRoot == nil ? .neutral : .accent
                )
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    quickFact(title: "XML", value: selectionState(for: viewModel.xmlURL))
                    quickFact(title: "Destination", value: selectionState(for: viewModel.destinationURL))
                    quickFact(title: "Relink", value: viewModel.options.smartRelink ? "Enabled" : "Off")
                    quickFact(title: "Preserve", value: viewModel.options.preserveStructure ? viewModel.options.preserveMode.displayName : "Flat Copy")
                }

                VStack(alignment: .leading, spacing: 10) {
                    quickFact(title: "XML", value: selectionState(for: viewModel.xmlURL))
                    quickFact(title: "Destination", value: selectionState(for: viewModel.destinationURL))
                    quickFact(title: "Relink", value: viewModel.options.smartRelink ? "Enabled" : "Off")
                    quickFact(title: "Preserve", value: viewModel.options.preserveStructure ? viewModel.options.preserveMode.displayName : "Flat Copy")
                }
            }
        }
    }

    private var workspaceSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: workspaceSpacing) {
                VStack(alignment: .leading, spacing: 24) {
                    sourceSection(viewModel: viewModel)
                    logSection(viewModel: viewModel)
                }
                .frame(width: primaryColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 24) {
                    runConsoleSection(viewModel: viewModel)
                    optionsSection(viewModel: viewModel)
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 24) {
                sourceSection(viewModel: viewModel)
                runConsoleSection(viewModel: viewModel)
                optionsSection(viewModel: viewModel)
                logSection(viewModel: viewModel)
            }
        }
    }

    private func sourceSection(viewModel: CollectMediaViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                eyebrow: "Setup",
                title: "Sources and destination",
                body: "Point the run at an XML, destination folder, and optional relink root."
            )

            sourceRow(
                title: "Premiere FCP XML",
                value: compactPath(viewModel.xmlURL),
                buttonTitle: "Select XML",
                action: { viewModel.selectXML() }
            )

            sourceRow(
                title: "Destination Folder",
                value: compactPath(viewModel.destinationURL),
                buttonTitle: "Select Destination",
                action: { viewModel.selectDestination() }
            )

            sourceRow(
                title: "Search Root",
                value: compactPath(viewModel.options.searchRoot) ?? "Optional",
                buttonTitle: "Select Search Root",
                action: { viewModel.selectSearchRoot() },
                secondaryButtonTitle: viewModel.options.searchRoot == nil ? nil : "Clear",
                secondaryAction: { viewModel.clearSearchRoot() }
            )

            Divider()

            sourceRow(
                title: "EDL Placeholder",
                value: compactPath(viewModel.edlURL) ?? "Not selected",
                buttonTitle: "Select EDL",
                action: { viewModel.selectEDL() }
            )
        }
        .padding(22)
        .background(workspacePanel)
    }

    private func optionsSection(viewModel: CollectMediaViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                eyebrow: "Controls",
                title: "Run options",
                body: "Keep the most-used toggles visible. Expand the rest only when needed."
            )

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Preserve folder structure", isOn: $viewModel.options.preserveStructure)
                Toggle("Skip duplicates", isOn: $viewModel.options.skipDuplicates)
                Toggle("Smart relink missing files", isOn: $viewModel.options.smartRelink)
            }

            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Use ffprobe for duration and timecode matching", isOn: $viewModel.options.useFFProbe)
                        .disabled(!viewModel.ffProbeAvailable)

                    Picker("Preserve mode", selection: $viewModel.options.preserveMode) {
                        ForEach(CollectPreserveMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .disabled(!viewModel.options.preserveStructure)

                    Stepper(value: $viewModel.options.tailN, in: 1...20) {
                        Text("Tail depth: \(viewModel.options.tailN) folders")
                    }
                    .disabled(!viewModel.options.preserveStructure || viewModel.options.preserveMode != .tailN)

                    if !viewModel.ffProbeAvailable {
                        Label("ffprobe was not found on this Mac, so metadata-assisted matching is unavailable.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
            } label: {
                Label("Advanced options", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(22)
        .background(workspacePanel)
    }

    private func runConsoleSection(viewModel: CollectMediaViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                eyebrow: "Run Console",
                title: commandTitle,
                body: commandSubtitle
            )

            HStack(spacing: 12) {
                Button("Collect") {
                    viewModel.startCollect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(!viewModel.canCollect)

                Button("Stop") {
                    viewModel.stopCollect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!viewModel.isCollecting)
            }

            groupedPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("State")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.isCollecting ? "Running" : (viewModel.canCollect ? "Ready" : "Waiting"))
                                .font(.headline.weight(.semibold))
                        }

                        Spacer()

                        capabilityBadge(
                            title: viewModel.isCollecting ? "Live Run" : "Idle",
                            tone: viewModel.isCollecting ? .accent : .neutral
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        summaryLine(title: "XML Source", value: compactPath(viewModel.xmlURL) ?? "Not selected")
                        summaryLine(title: "Destination", value: compactPath(viewModel.destinationURL) ?? "Not selected")
                        summaryLine(title: "Search Root", value: compactPath(viewModel.options.searchRoot) ?? "Optional")
                    }
                }
            }

            groupedPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Run Status")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(viewModel.progress.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(spacing: 10) {
                        if viewModel.isCollecting, viewModel.progress.totalUnitCount > 0 {
                            ProgressView(
                                value: Double(viewModel.progress.completedUnitCount),
                                total: Double(viewModel.progress.totalUnitCount)
                            )
                        } else if viewModel.isCollecting {
                            ProgressView()
                        } else {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 8)
                        }

                        HStack {
                            Text(progressLabel(for: viewModel.progress))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.isCollecting ? "Running" : "Idle")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(viewModel.isCollecting ? .primary : .secondary)
                        }
                    }

                    if let currentItem = viewModel.progress.currentItem, !currentItem.isEmpty {
                        Text(currentItem)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        compactStat(title: "Found", value: viewModel.progress.counts.found)
                        compactStat(title: "Copied", value: viewModel.progress.counts.copied)
                        compactStat(title: "Missing", value: viewModel.progress.counts.missing)
                        compactStat(title: "Skipped", value: viewModel.progress.counts.skipped)
                    }
                }
            }
        }
        .padding(22)
        .background(workspacePanel)
    }

    private func logSection(viewModel: CollectMediaViewModel) -> some View {
        let visibleLogs = showFullLog ? viewModel.logs : Array(viewModel.logs.suffix(8))

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader(
                    eyebrow: "Trace",
                    title: "Run log",
                    body: "Recent activity and status messages from the current or last collect run."
                )

                Spacer()

                Button(showFullLog ? "Show Less" : "Show Full Log") {
                    showFullLog.toggle()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(visibleLogs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
                .padding(14)
            }
            .frame(minHeight: showFullLog ? 260 : 150)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(22)
        .background(workspacePanel)
    }

    private func sourceRow(
        title: String,
        value: String?,
        buttonTitle: String,
        action: @escaping () -> Void,
        secondaryButtonTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 12) {
                Text(value ?? "Not selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(buttonTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)

                    if let secondaryButtonTitle, let secondaryAction {
                        Button(secondaryButtonTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(eyebrow: String, title: String, body: String) -> some View {
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
    }

    private func quickFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
    }

    private func summaryLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func compactStat(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func groupedPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private var statusBadge: some View {
        capabilityBadge(title: commandTitle, tone: viewModel.isCollecting ? .accent : .neutral)
    }

    private func capabilityBadge(title: String, tone: BadgeTone) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.background)
            .foregroundStyle(tone.foreground)
            .clipShape(Capsule())
    }

    private func selectionState(for url: URL?) -> String {
        url == nil ? "Waiting" : "Selected"
    }

    private func compactPath(_ url: URL?) -> String? {
        url?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func progressLabel(for progress: CollectProgress) -> String {
        guard progress.totalUnitCount > 0 else {
            return viewModel.isCollecting ? "Preparing run" : "Waiting to start"
        }
        return "\(progress.completedUnitCount) of \(progress.totalUnitCount)"
    }

    private var commandTitle: String {
        if viewModel.isCollecting {
            return "Collect Running"
        }
        if viewModel.canCollect {
            return "Ready to Collect"
        }
        return "Waiting for Input"
    }

    private var commandSubtitle: String {
        if viewModel.isCollecting {
            return "The current run is active. Progress and logs update live."
        }
        if viewModel.canCollect {
            return "XML and destination are set. You can start the run now."
        }
        return "Select an XML file and a destination folder to enable collecting."
    }

    private var workspacePanel: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.accentColor.opacity(0.05))
    }
}

private enum BadgeTone {
    case neutral
    case accent
    case warning

    var background: Color {
        switch self {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .accent:
            return Color.accentColor.opacity(0.14)
        case .warning:
            return Color.orange.opacity(0.14)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .warning:
            return .orange
        }
    }
}
