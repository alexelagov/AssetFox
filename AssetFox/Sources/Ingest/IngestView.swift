import SwiftUI

struct IngestView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = IngestViewModel()
    @State private var jobName = ""
    @State private var reelName = ""
    @State private var verificationEnabled = true
    @State private var preserveFolderStructure = true
    @State private var createReport = true

    private let primaryColumnWidth: CGFloat = 720
    private let sidebarWidth: CGFloat = 360

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerBlock
                workspaceSection
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.reconcilePersistedSelections()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                viewModel.reconcilePersistedSelections()
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Ingest", systemImage: "square.and.arrow.down.on.square")
                .font(.system(size: 28, weight: .semibold))

            Text("Prepare a future ingest workflow for source pickup, destination routing, metadata, copy behavior, and run tracking.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)

            HStack(spacing: 10) {
                badge(preserveFolderStructure ? "Folder Structure Preserved" : "Flat Copy Mode", tone: .accent)
                badge(viewModel.preflightStatusTitle, tone: statusBadgeTone)
                badge(viewModel.sourceURL == nil ? "Source Unset" : "Source Ready", tone: sourceBadgeTone)
                badge(verificationEnabled ? "SHA-256 \(viewModel.verificationStateTitle)" : "SHA-256 Disabled", tone: verificationBadgeTone)
            }
        }
    }

    private var workspaceSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    sourceSection
                    metadataSection
                    progressSection
                }
                .frame(width: primaryColumnWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 24) {
                    destinationSection
                    copySettingsSection
                    resultSummarySection
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 24) {
                sourceSection
                destinationSection
                metadataSection
                copySettingsSection
                progressSection
                resultSummarySection
            }
        }
    }

    private var sourceSection: some View {
        sectionCard(
            eyebrow: "Source",
            title: "Media source",
            body: "Select or mount a source volume, card, or watch folder."
        ) {
            LabeledContent("Selected source") {
                Text(viewModel.compactPath(viewModel.sourceURL) ?? "No source selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(viewModel.sourceURL == nil ? .secondary : .primary)
            }

            HStack(spacing: 10) {
                Button("Choose Source") {
                    viewModel.selectSource()
                }
                .buttonStyle(.borderedProminent)
                .help("Choose the source folder or volume to scan and ingest.")

                Button("Rescan") {
                    viewModel.rescanSource()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.sourceURL == nil || viewModel.canCancel)
                .help("Scan the selected source again and refresh file, folder, and size totals.")

                if viewModel.isScanningSource {
                    Button("Cancel") {
                        viewModel.cancelCurrentJob()
                    }
                    .buttonStyle(.bordered)
                    .help("Cancel the current source scan and keep any partial scan information.")
                }
            }

            HStack {
                statPill(title: "Files", value: "\(viewModel.scanResult.fileCount)")
                statPill(title: "Folders", value: "\(viewModel.scanResult.folderCount)")
                statPill(title: "Size", value: viewModel.formattedTotalSize())
            }

            if viewModel.isScanningSource {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning source recursively...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let sourceScanError = viewModel.sourceScanError {
                Label(sourceScanError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("The selected source is scanned recursively to estimate files, folders, and total size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationSection: some View {
        sectionCard(
            eyebrow: "Destination",
            title: "Target path",
            body: "Define where the ingest run should copy media and support files."
        ) {
            LabeledContent("Destination") {
                Text(viewModel.compactPath(viewModel.destinationURL) ?? "No destination selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(viewModel.destinationURL == nil ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
            }

            Button("Choose Destination") {
                viewModel.selectDestination()
            }
            .buttonStyle(.borderedProminent)
            .help("Choose the destination folder where ingested media should be copied.")

            HStack {
                statPill(title: "Free Space", value: viewModel.formattedDestinationFreeSpace())
                statPill(title: "Writable", value: writableLabel)
            }

            Text("Preflight checks destination writability and available space before any ingest logic is allowed to run. Reports are written as CSV for file-level rows and TXT for the human summary.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataSection: some View {
        sectionCard(
            eyebrow: "Job Metadata",
            title: "Job details",
            body: "Capture the metadata that should travel with an ingest run."
        ) {
            TextField("Job Name", text: $jobName)
                .textFieldStyle(.roundedBorder)

            TextField("Reel, Card Name", text: $reelName)
                .textFieldStyle(.roundedBorder)

            Text("Placeholder: operator, shoot day, notes, tags, and presets can be added here later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var copySettingsSection: some View {
        sectionCard(
            eyebrow: "Copy Settings",
            title: "Transfer behavior",
            body: "Configure verification, folder handling, and reporting."
        ) {
            Toggle("Verify copied files (SHA-256)", isOn: $verificationEnabled)
                .disabled(viewModel.canCancel)
            Toggle("Preserve folder structure", isOn: $preserveFolderStructure)
                .disabled(viewModel.canCancel)
            Toggle("Generate ingest report", isOn: $createReport)
                .disabled(viewModel.canCancel)

            Picker("Conflict handling", selection: $viewModel.conflictMode) {
                ForEach(IngestConflictMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .help("If a destination file already exists, AssetFox compares SHA-256 first. Matching files are skipped. Different files are only replaced when Overwrite Existing is selected.")

            Text(copySettingsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        sectionCard(
            eyebrow: "Progress",
            title: "Run status",
            body: "Track ingest progress, throughput, and current activity."
        ) {
            if viewModel.isScanningSource {
                ProgressView()
            } else if viewModel.isCopying || viewModel.copiedFilesCount > 0 || viewModel.failedFilesCount > 0 || viewModel.skippedFilesCount > 0 {
                ProgressView(value: viewModel.copyProgressFraction, total: 1)
            } else {
                ProgressView(value: viewModel.copyResult == nil ? 0 : 1, total: 1)
            }

            HStack {
                statPill(title: "Files Copied", value: "\(viewModel.copyProgress.copiedFiles)/\(viewModel.copyProgress.totalFiles)")
                statPill(title: "Verified", value: "\(viewModel.copyProgress.verifiedFiles)")
                statPill(title: "Bytes Copied", value: "\(viewModel.formattedCopiedBytes()) / \(viewModel.formattedCopyTotalBytes())")
                statPill(title: "State", value: viewModel.verificationStateTitle)
            }

            LabeledContent("Current file") {
                Text(viewModel.currentCopyPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(viewModel.isCopying ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }

            if let detail = viewModel.copyProgress.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(progressDetailColor)
            }

            HStack(spacing: 10) {
                Button("Start Ingest") {
                    viewModel.startIngestCopy(
                        jobName: jobName,
                        reelName: reelName,
                        priority: "Standard",
                        verificationEnabled: verificationEnabled,
                        preserveFolderStructure: preserveFolderStructure,
                        createReport: createReport
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(startButtonTint)
                .disabled(!viewModel.canStartIngest)
                .help("Start copying the scanned source into the selected destination using the current ingest settings.")

                if viewModel.canCancel {
                    Button("Cancel") {
                        viewModel.cancelCurrentJob()
                    }
                    .buttonStyle(.bordered)
                    .help("Cancel the current ingest run and preserve partial progress and reports.")
                }

                Text(progressHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastMeaningfulError = viewModel.lastMeaningfulError {
                Label(lastMeaningfulError, systemImage: viewModel.jobStatus == .failed ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.jobStatus == .failed ? .red : .orange)
            }
        }
    }

    private var resultSummarySection: some View {
        sectionCard(
            eyebrow: "Result Summary",
            title: "Run summary",
            body: "Review validation output, copy status, and SHA-256 verification results."
        ) {
            if let copyError = viewModel.copyError {
                VStack(alignment: .leading, spacing: 12) {
                    statusBanner
                    summaryMetricsGrid
                    Label(copyError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            } else if let copyResult = viewModel.copyResult {
                VStack(alignment: .leading, spacing: 12) {
                    statusBanner
                    summaryMetricsGrid

                    LabeledContent("Destination") {
                        Text(viewModel.compactPath(copyResult.destinationURL) ?? copyResult.destinationURL.path)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }

                    if !viewModel.verificationIssueRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Verification issues")
                                .font(.subheadline.weight(.semibold))

                            ForEach(viewModel.verificationIssueRecords.prefix(5)) { record in
                                Label(verificationMessage(for: record), systemImage: "xmark.octagon.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            } else if viewModel.jobStatus == .cancelled {
                VStack(alignment: .leading, spacing: 12) {
                    statusBanner
                    summaryMetricsGrid
                }
            } else if viewModel.preflightIssues.isEmpty {
                Label("Preflight checks are clear. Source and destination are ready for ingest copy.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.preflightIssues) { issue in
                        Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                    }
                }
            }

            if let reportError = viewModel.reportError {
                Label("Report warning: \(reportError)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            LabeledContent("Report folder") {
                Text(viewModel.compactPath(viewModel.reportDestinationURL) ?? "Default: destination reports folder")
                    .font(.caption.monospaced())
                    .foregroundStyle(viewModel.reportDestinationURL == nil ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
            }

            if let reportFiles = viewModel.reportFiles {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Report output")
                        .font(.subheadline.weight(.semibold))

                    Label("TXT: \(viewModel.compactPath(reportFiles.textURL) ?? reportFiles.textURL.path)", systemImage: "doc.plaintext")
                        .font(.caption)
                    Label("CSV: \(viewModel.compactPath(reportFiles.csvURL) ?? reportFiles.csvURL.path)", systemImage: "tablecells")
                        .font(.caption)
                }
            }

            if !viewModel.runWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Warnings")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(viewModel.runWarnings.prefix(5)), id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button("Choose Report Folder") {
                    viewModel.selectReportDestination()
                }
                .buttonStyle(.bordered)
                .help("Choose a custom folder for CSV, TXT, and JSON ingest reports.")

                HStack(spacing: 10) {
                    Button("Use Default") {
                        viewModel.clearReportDestination()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.reportDestinationURL == nil)
                    .help("Reset report output back to the default reports folder inside the destination.")

                    Button("Reveal in Finder") {
                        viewModel.revealReport()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.reportFiles == nil)
                    .help("Reveal the current ingest report folder in Finder.")
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        eyebrow: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.accentColor.opacity(0.05))
        )
    }

    private func badge(_ title: String, tone: IngestBadgeTone) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.background)
            .foregroundStyle(tone.foreground)
            .clipShape(Capsule())
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var writableLabel: String {
        guard let destinationWritable = viewModel.destinationWritable else { return "Unknown" }
        return destinationWritable ? "Yes" : "No"
    }

    private var progressStateLabel: String {
        if viewModel.isScanningSource {
            return "Scanning"
        }
        if viewModel.isCopying {
            return viewModel.verificationStateTitle
        }
        if viewModel.copyResult != nil {
            return "Completed"
        }
        return "Idle"
    }

    private var progressHelpText: String {
        if viewModel.isScanningSource {
            return "Source scan is still running."
        }
        if viewModel.isCopying {
            return verificationEnabled
                ? "Copy and verification are running in the background."
                : "Copy is running in the background without post-copy verification."
        }
        if viewModel.hasBlockingPreflightIssues {
            return "Resolve the blocking preflight issues to enable ingest."
        }
        return verificationEnabled
            ? "Ready to copy files recursively and verify each file with SHA-256."
            : "Ready to copy files recursively without post-copy verification."
    }

    private var copySettingsHelpText: String {
        let structureText = preserveFolderStructure
            ? "preserves relative paths"
            : "flattens files into the destination root"
        let verificationText = verificationEnabled
            ? "runs SHA-256 after each copied file"
            : "skips post-copy verification"
        let reportText = createReport
            ? "writes CSV, TXT, and JSON reports"
            : "does not write ingest reports"

        return "This stage copies files recursively, \(structureText), \(verificationText), and \(reportText). Existing destination files are still checksum-checked before they are treated as safe skips."
    }

    private var verificationBadgeTone: IngestBadgeTone {
        if let jobStatus = viewModel.jobStatus {
            switch jobStatus {
            case .success:
                return .success
            case .successWithWarnings, .failed, .cancelled:
                return .warning
            }
        }
        if viewModel.canStartIngest && verificationEnabled {
            return .success
        }
        if viewModel.workflowState == .verifying || viewModel.workflowState == .copying {
            return .accent
        }
        if let copyResult = viewModel.copyResult,
           copyResult.mismatchCount == 0,
           copyResult.verificationFailureCount == 0 {
            return .success
        }
        if viewModel.copyProgress.mismatchCount > 0 || viewModel.copyProgress.verificationFailureCount > 0 {
            return .warning
        }
        return .neutral
    }

    private var statusBadgeTone: IngestBadgeTone {
        switch viewModel.workflowState {
        case .failed, .completedWithWarnings, .cancelled:
            return .warning
        case .completed, .ready:
            return .success
        case .scanning, .copying, .verifying:
            return .accent
        case .idle:
            return viewModel.hasBlockingPreflightIssues ? .warning : .neutral
        }
    }

    private var sourceBadgeTone: IngestBadgeTone {
        viewModel.sourceURL == nil ? .neutral : .success
    }

    private var startButtonTint: Color {
        viewModel.canStartIngest ? .green : .accentColor
    }

    private var progressDetailColor: Color {
        if viewModel.jobStatus == .failed {
            return .red
        }
        if viewModel.copyProgress.mismatchCount > 0 || viewModel.copyProgress.verificationFailureCount > 0 {
            return .orange
        }
        return .secondary
    }

    private var statusBanner: some View {
        Label(statusBannerText, systemImage: statusBannerIcon)
            .foregroundStyle(statusBannerColor)
    }

    private var summaryMetricsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statPill(title: "Scanned", value: "\(viewModel.totalScannedFilesCount)")
                statPill(title: "Copied", value: "\(viewModel.copiedFilesCount)")
                statPill(title: "Verified", value: "\(viewModel.verifiedFilesCount)")
            }

            HStack {
                statPill(title: "Skipped", value: "\(viewModel.skippedFilesCount)")
                statPill(title: "Failed", value: "\(viewModel.failedFilesCount)")
                statPill(title: "Mismatches", value: "\(viewModel.mismatchesCount)")
            }

            HStack {
                statPill(title: "Elapsed", value: viewModel.formattedElapsedTime())
            }
        }
    }

    private func summaryTitle(for result: IngestCopyResult) -> String {
        if result.mismatchCount == 0 && result.verificationFailureCount == 0 {
            return "Ingest completed. \(result.copiedFiles) of \(result.totalFiles) files were copied and verified."
        }
        return "Ingest completed with verification issues. Review mismatches and failures below."
    }

    private var statusBannerText: String {
        switch viewModel.jobStatus {
        case .success:
            return "Success. All copied files completed SHA-256 verification."
        case .successWithWarnings:
            return summaryTitle(for: viewModel.copyResult!)
        case .failed:
            return "Failed. The ingest run did not finish cleanly."
        case .cancelled:
            return "Cancelled. Partial progress and a partial report were preserved."
        case nil:
            return "No ingest run has completed yet."
        }
    }

    private var statusBannerIcon: String {
        switch viewModel.jobStatus {
        case .success:
            return "checkmark.seal.fill"
        case .successWithWarnings:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "slash.circle.fill"
        case nil:
            return "clock"
        }
    }

    private var statusBannerColor: Color {
        switch viewModel.jobStatus {
        case .success:
            return .green
        case .successWithWarnings, .cancelled:
            return .orange
        case .failed:
            return .red
        case nil:
            return .secondary
        }
    }

    private func verificationMessage(for record: IngestFileVerificationRecord) -> String {
        switch record.state {
        case .verified:
            return "\(record.relativePath) verified"
        case .copiedWithoutVerification:
            return "\(record.relativePath) copied without verification"
        case .mismatch:
            return "\(record.relativePath) failed SHA-256 verification"
        case .failed(let reason):
            return "\(record.relativePath) could not be verified: \(reason)"
        case .skippedExisting:
            return "\(record.relativePath) was skipped"
        }
    }
}

private enum IngestBadgeTone {
    case neutral
    case accent
    case success
    case warning

    var background: Color {
        switch self {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .accent:
            return Color.accentColor.opacity(0.14)
        case .success:
            return Color.green.opacity(0.16)
        case .warning:
            return Color.orange.opacity(0.16)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }
}
