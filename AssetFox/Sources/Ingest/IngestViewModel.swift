import AppKit
import Darwin
import Observation

enum IngestJobStatus: String {
    case success = "Success"
    case successWithWarnings = "Success with Warnings"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

enum IngestWorkflowState: String {
    case idle = "Idle"
    case scanning = "Scanning"
    case ready = "Ready"
    case copying = "Copying"
    case verifying = "Verifying"
    case completed = "Completed"
    case completedWithWarnings = "Completed with Warnings"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

@MainActor
@Observable
final class IngestViewModel {
    private enum PersistedPathKey {
        static let source = "assetfox.ingest.sourcePath"
        static let destination = "assetfox.ingest.destinationPath"
        static let reportDestination = "assetfox.ingest.reportDestinationPath"
    }

    var sourceURL: URL?
    var destinationURL: URL?
    var reportDestinationURL: URL?
    var conflictMode: IngestConflictMode = .skipExisting
    var workflowState: IngestWorkflowState = .idle
    var scanResult = IngestSourceScanResult.empty
    var sourceScanError: String?
    var preflightIssues: [IngestPreflightIssue] = []
    var destinationFreeBytes: Int64?
    var destinationWritable: Bool?
    var copyProgress = IngestCopyProgress.idle
    var copyResult: IngestCopyResult?
    var copyError: String?
    var elapsedTime: TimeInterval = 0
    var reportFiles: IngestReportFiles?
    var reportError: String?
    var currentRunRecords: [IngestFileVerificationRecord] = []
    var runWarnings: [String] = []
    var runErrors: [String] = []
    var lastMeaningfulError: String?
    var verificationEnabledForRun = true
    var preserveFolderStructureForRun = true
    var createReportForRun = true

    @ObservationIgnored private let sourceScanner: IngestSourceScanner
    @ObservationIgnored private let copier: IngestCopier
    @ObservationIgnored private let reportWriter: IngestReportWriter
    @ObservationIgnored private var sourceScanTask: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var ingestStartedAt: Date?

    init(
        sourceScanner: IngestSourceScanner = IngestSourceScanner(),
        copier: IngestCopier = IngestCopier(),
        reportWriter: IngestReportWriter = IngestReportWriter()
    ) {
        self.sourceScanner = sourceScanner
        self.copier = copier
        self.reportWriter = reportWriter
        restorePersistedSelections()
        refreshPreflight()
    }

    var isScanningSource: Bool {
        workflowState == .scanning
    }

    var isCopying: Bool {
        workflowState == .copying || workflowState == .verifying
    }

    var canCancel: Bool {
        isScanningSource || isCopying
    }

    var jobStatus: IngestJobStatus? {
        switch workflowState {
        case .completed:
            return .success
        case .completedWithWarnings:
            return .successWithWarnings
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        default:
            return nil
        }
    }

    func selectSource() {
        let panel = configuredFolderPanel(title: "Select ingest source", initialURL: sourceURL)

        if panel.runModal() == .OK {
            setSourceURL(panel.url)
            resetRunState(clearReports: true)
            refreshPreflight()
            startSourceScan()
        }
    }

    func selectDestination() {
        let panel = configuredFolderPanel(title: "Select ingest destination", initialURL: destinationURL)

        if panel.runModal() == .OK {
            setDestinationURL(panel.url)
            resetRunState(clearReports: true)
            refreshPreflight()
        }
    }

    func selectReportDestination() {
        let panel = configuredFolderPanel(title: "Select report output folder", initialURL: reportDestinationURL ?? destinationURL)

        if panel.runModal() == .OK {
            setReportDestinationURL(panel.url)
            refreshPreflight()
        }
    }

    func clearReportDestination() {
        setReportDestinationURL(nil)
        refreshPreflight()
    }

    func reconcilePersistedSelections() {
        guard !canCancel else { return }

        let fileManager = FileManager.default
        var didReset = false

        if let sourceURL, !fileManager.fileExists(atPath: sourceURL.path) {
            setSourceURL(nil)
            scanResult = .empty
            sourceScanError = nil
            didReset = true
        }

        if let destinationURL, !fileManager.fileExists(atPath: destinationURL.path) {
            setDestinationURL(nil)
            didReset = true
        }

        if let reportDestinationURL, !fileManager.fileExists(atPath: reportDestinationURL.path) {
            setReportDestinationURL(nil)
            didReset = true
        }

        if didReset {
            resetRunState(clearReports: false)
        }

        refreshPreflight()
    }

    func compactPath(_ url: URL?) -> String? {
        url?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    func rescanSource() {
        resetRunState(clearReports: false)
        startSourceScan()
    }

    func cancelCurrentJob() {
        if isScanningSource {
            sourceScanTask?.cancel()
        } else if isCopying {
            copyTask?.cancel()
        }
    }

    func formattedTotalSize() -> String {
        ByteCountFormatter.string(fromByteCount: scanResult.totalBytes, countStyle: .file)
    }

    func formattedDestinationFreeSpace() -> String {
        guard let destinationFreeBytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: destinationFreeBytes, countStyle: .file)
    }

    var hasBlockingPreflightIssues: Bool {
        preflightIssues.contains(where: { $0.severity == .error })
    }

    var preflightStatusTitle: String {
        switch workflowState {
        case .idle:
            if hasBlockingPreflightIssues {
                return "Preflight Blocked"
            }
            return preflightIssues.isEmpty ? "Preflight Ready" : "Preflight Warning"
        case .ready:
            return "Ready"
        case .scanning:
            return "Scanning Source"
        case .copying:
            return "Copying"
        case .verifying:
            return "Verifying"
        case .completed:
            return "Success"
        case .completedWithWarnings:
            return "Success with Warnings"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var canStartIngest: Bool {
        !isScanningSource && !isCopying && !hasBlockingPreflightIssues && sourceURL != nil && destinationURL != nil
    }

    var copyProgressFraction: Double {
        guard copyProgress.totalFiles > 0 else { return 0 }
        guard verificationEnabledForRun else {
            return Double(copyProgress.copiedFiles) / Double(copyProgress.totalFiles)
        }
        let completedVerification = copyProgress.verifiedFiles + copyProgress.mismatchCount + copyProgress.verificationFailureCount
        let completedSteps = min(copyProgress.copiedFiles + completedVerification, copyProgress.totalFiles * 2)
        return Double(completedSteps) / Double(copyProgress.totalFiles * 2)
    }

    var currentCopyPath: String {
        copyProgress.currentFilePath ?? scanResult.lastScannedPath ?? "Waiting to start"
    }

    var verificationStateTitle: String {
        switch workflowState {
        case .copying:
            return "Copying"
        case .verifying:
            return verificationEnabledForRun ? "Verifying" : "Copying"
        case .completed:
            return verificationEnabledForRun ? "Verified" : "Not Verified"
        case .completedWithWarnings:
            return verificationEnabledForRun ? "Issues Found" : "Completed With Warnings"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .scanning:
            return "Scanning"
        case .ready:
            return "Ready"
        case .idle:
            return "Idle"
        }
    }

    func formattedCopiedBytes() -> String {
        ByteCountFormatter.string(fromByteCount: copyProgress.copiedBytes, countStyle: .file)
    }

    func formattedCopyTotalBytes() -> String {
        ByteCountFormatter.string(fromByteCount: copyProgress.totalBytes, countStyle: .file)
    }

    var verificationIssueRecords: [IngestFileVerificationRecord] {
        let records = copyResult?.verificationRecords ?? currentRunRecords
        return records.filter {
            switch $0.state {
            case .verified, .copiedWithoutVerification, .skippedExisting:
                return false
            case .mismatch, .failed:
                return true
            }
        }
    }

    var failedFilesCount: Int {
        copyResult?.verificationFailureCount ?? copyProgress.verificationFailureCount
    }

    var mismatchesCount: Int {
        copyResult?.mismatchCount ?? copyProgress.mismatchCount
    }

    var skippedFilesCount: Int {
        copyResult?.skippedFiles ?? currentRunRecords.filter {
            if case .skippedExisting = $0.state { return true }
            return false
        }.count
    }

    var copiedFilesCount: Int {
        copyResult?.copiedFiles ?? copyProgress.copiedFiles
    }

    var verifiedFilesCount: Int {
        copyResult?.verifiedFiles ?? copyProgress.verifiedFiles
    }

    var totalScannedFilesCount: Int {
        scanResult.fileCount
    }

    func formattedElapsedTime() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = elapsedTime >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: elapsedTime) ?? "0s"
    }

    func startIngestCopy(
        jobName: String,
        reelName: String,
        priority: String,
        verificationEnabled: Bool,
        preserveFolderStructure: Bool,
        createReport: Bool
    ) {
        guard let sourceURL, let destinationURL, canStartIngest else { return }

        copyTask?.cancel()
        workflowState = .copying
        copyError = nil
        copyResult = nil
        elapsedTime = 0
        ingestStartedAt = Date()
        reportFiles = nil
        reportError = nil
        currentRunRecords = []
        runWarnings = scanResult.warnings
        runErrors = []
        lastMeaningfulError = nil
        verificationEnabledForRun = verificationEnabled
        preserveFolderStructureForRun = preserveFolderStructure
        createReportForRun = createReport
        copyProgress = IngestCopyProgress(
            copiedFiles: 0,
            totalFiles: scanResult.fileCount,
            copiedBytes: 0,
            totalBytes: scanResult.totalBytes,
            verifiedFiles: 0,
            mismatchCount: 0,
            verificationFailureCount: 0,
            currentFilePath: nil,
            phase: .idle,
            detail: "Preparing ingest run",
            latestRecord: nil,
            warnings: runWarnings,
            errors: []
        )

        let metadata = IngestJobMetadata(jobName: jobName, reelName: reelName, priority: priority)
        let settings = IngestJobSettings(
            conflictMode: conflictMode.rawValue,
            checksumVerification: verificationEnabled ? "SHA-256" : "Disabled",
            preserveFolderStructure: preserveFolderStructure,
            createReport: createReport,
            requestedReportRootPath: reportDestinationURL?.path
        )

        copyTask = Task { [weak self, copier, reportWriter, conflictMode] in
            guard let self else { return }
            do {
                let result = try await copier.copyRecursively(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    conflictMode: conflictMode,
                    verificationEnabled: verificationEnabled,
                    preserveFolderStructure: preserveFolderStructure
                ) { progress in
                    await MainActor.run {
                        self.copyProgress = progress
                        self.runWarnings = progress.warnings
                        self.runErrors = progress.errors
                        if let latestRecord = progress.latestRecord {
                            self.currentRunRecords.append(latestRecord)
                        }
                        self.lastMeaningfulError = progress.errors.last ?? progress.warnings.last
                        self.workflowState = progress.phase == .verifying ? .verifying : .copying
                    }
                }

                guard !Task.isCancelled else { return }
                self.copyResult = result
                self.elapsedTime = result.elapsedTime
                self.runWarnings = result.warnings
                self.runErrors = result.errors
                self.currentRunRecords = result.verificationRecords
                self.copyProgress = IngestCopyProgress(
                    copiedFiles: result.copiedFiles,
                    totalFiles: result.totalFiles,
                    copiedBytes: result.copiedBytes,
                    totalBytes: result.totalBytes,
                    verifiedFiles: result.verifiedFiles,
                    mismatchCount: result.mismatchCount,
                    verificationFailureCount: result.verificationFailureCount,
                    currentFilePath: nil,
                    phase: .completed,
                    detail: {
                        if verificationEnabled {
                            return result.mismatchCount == 0 && result.verificationFailureCount == 0
                                ? "SHA-256 verification complete"
                                : "Verification issues detected"
                        }
                        return result.errors.isEmpty ? "Copy completed without post-copy verification" : "Copy completed with issues"
                    }(),
                    latestRecord: result.verificationRecords.last,
                    warnings: result.warnings,
                    errors: result.errors
                )
                self.lastMeaningfulError = result.errors.last ?? result.warnings.last
                self.workflowState = (result.skippedFiles > 0 || result.mismatchCount > 0 || result.verificationFailureCount > 0 || !result.errors.isEmpty) ? .completedWithWarnings : .completed
                self.writeReport(
                    metadata: metadata,
                    settings: settings,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    reportWriter: reportWriter
                )
                self.copyTask = nil
            } catch is CancellationError {
                self.elapsedTime = self.ingestStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.lastMeaningfulError = "The ingest job was cancelled."
                self.workflowState = .cancelled
                self.writeReport(
                    metadata: metadata,
                    settings: settings,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    reportWriter: reportWriter
                )
                self.copyTask = nil
            } catch {
                if let partialSnapshot = (error as NSError).userInfo["partialSnapshot"] as? IngestPartialRunSnapshot {
                    self.applyPartialSnapshot(partialSnapshot)
                }
                self.copyError = error.localizedDescription
                self.runErrors.append(error.localizedDescription)
                self.lastMeaningfulError = error.localizedDescription
                self.elapsedTime = self.ingestStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.workflowState = .failed
                self.writeReport(
                    metadata: metadata,
                    settings: settings,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    reportWriter: reportWriter
                )
                self.copyTask = nil
            }
        }
    }

    func revealReport() {
        guard let targetURL = reportFiles?.directoryURL ?? reportFiles?.textURL ?? reportFiles?.jsonURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }

    private func startSourceScan() {
        guard let sourceURL else { return }

        sourceScanTask?.cancel()
        workflowState = .scanning
        sourceScanError = nil
        scanResult = .empty
        lastMeaningfulError = nil
        refreshPreflight()

        sourceScanTask = Task { [weak self, sourceScanner] in
            guard let self else { return }
            do {
                let result = try await sourceScanner.scan(sourceURL: sourceURL) { partialResult in
                    await MainActor.run {
                        self.scanResult = partialResult
                        self.refreshPreflight()
                    }
                }
                guard !Task.isCancelled else { return }
                self.scanResult = result
                self.sourceScanError = result.warnings.last
                self.refreshPreflight()
                self.workflowState = self.deriveNonRunningState()
                self.sourceScanTask = nil
            } catch is CancellationError {
                self.sourceScanError = "Source scan was cancelled."
                self.lastMeaningfulError = self.sourceScanError
                self.refreshPreflight()
                self.workflowState = self.deriveNonRunningState(cancelled: true)
                self.sourceScanTask = nil
            } catch {
                self.sourceScanError = error.localizedDescription
                self.lastMeaningfulError = error.localizedDescription
                self.refreshPreflight()
                self.workflowState = .failed
                self.sourceScanTask = nil
            }
        }
    }

    private func resetRunState(clearReports: Bool) {
        copyTask?.cancel()
        sourceScanTask?.cancel()
        copyProgress = .idle
        copyResult = nil
        copyError = nil
        elapsedTime = 0
        ingestStartedAt = nil
        currentRunRecords = []
        runWarnings = []
        runErrors = []
        lastMeaningfulError = nil
        verificationEnabledForRun = true
        preserveFolderStructureForRun = true
        createReportForRun = true
        if clearReports {
            reportFiles = nil
            reportError = nil
        }
        workflowState = deriveNonRunningState()
    }

    private func refreshPreflight() {
        var issues: [IngestPreflightIssue] = []

        if sourceURL == nil {
            issues.append(IngestPreflightIssue(
                severity: .error,
                message: "Select a source folder before starting an ingest job."
            ))
        }

        if destinationURL == nil {
            issues.append(IngestPreflightIssue(
                severity: .error,
                message: "Select a destination folder before starting an ingest job."
            ))
        }

        if let sourceURL, let destinationURL, sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            issues.append(IngestPreflightIssue(
                severity: .error,
                message: "Source and destination cannot point to the same folder."
            ))
        }

        destinationFreeBytes = nil
        destinationWritable = nil

        if let destinationURL {
            let isWritable = FileManager.default.isWritableFile(atPath: destinationURL.path)
            destinationWritable = isWritable

            if !isWritable {
                issues.append(IngestPreflightIssue(
                    severity: .error,
                    message: "The selected destination is not writable."
                ))
            }

            if let freeBytes = availableCapacity(for: destinationURL) {
                destinationFreeBytes = freeBytes

                if workflowState != .scanning,
                   scanResult.totalBytes > 0,
                   freeBytes < scanResult.totalBytes {
                    issues.append(IngestPreflightIssue(
                        severity: .error,
                        message: "The destination does not have enough free space for the scanned source."
                    ))
                }
            } else if destinationURL != sourceURL {
                issues.append(IngestPreflightIssue(
                    severity: .warning,
                    message: "Free space could not be determined for the selected destination."
                ))
            }
        }

        if let reportDestinationURL, !FileManager.default.isWritableFile(atPath: reportDestinationURL.path) {
            issues.append(IngestPreflightIssue(
                severity: .warning,
                message: "The selected report folder is not writable. Reports will fall back automatically."
            ))
        }

        for warning in scanResult.warnings {
            issues.append(IngestPreflightIssue(
                severity: .warning,
                message: warning
            ))
        }

        if let sourceScanError, sourceScanError != "Source scan was cancelled." {
            issues.append(IngestPreflightIssue(
                severity: .warning,
                message: "Source scan warning: \(sourceScanError)"
            ))
        }

        preflightIssues = issues
        if workflowState == .idle || workflowState == .ready || workflowState == .cancelled {
            workflowState = deriveNonRunningState(cancelled: workflowState == .cancelled)
        }
    }

    private func deriveNonRunningState(cancelled: Bool = false) -> IngestWorkflowState {
        if cancelled {
            return .cancelled
        }
        if sourceURL != nil && destinationURL != nil && !hasBlockingPreflightIssues {
            return .ready
        }
        return .idle
    }

    private func applyPartialSnapshot(_ snapshot: IngestPartialRunSnapshot) {
        currentRunRecords = snapshot.records
        runWarnings = snapshot.warnings
        runErrors = snapshot.errors
        copyProgress = IngestCopyProgress(
            copiedFiles: snapshot.copiedFiles,
            totalFiles: snapshot.totalFiles,
            copiedBytes: snapshot.copiedBytes,
            totalBytes: snapshot.totalBytes,
            verifiedFiles: snapshot.verifiedFiles,
            mismatchCount: snapshot.mismatchCount,
            verificationFailureCount: snapshot.verificationFailureCount,
            currentFilePath: snapshot.currentFilePath,
            phase: snapshot.phase,
            detail: runErrors.last ?? runWarnings.last,
            latestRecord: snapshot.records.last,
            warnings: snapshot.warnings,
            errors: snapshot.errors
        )
    }

    private func currentWarnings() -> [String] {
        var warnings = runWarnings
        warnings.append(contentsOf: preflightIssues.filter { $0.severity == .warning }.map(\.message))
        if workflowState == .cancelled {
            warnings.append("The ingest job was cancelled before completion.")
        }
        if let reportError {
            warnings.append("Report generation warning: \(reportError)")
        }
        return Array(Set(warnings)).sorted()
    }

    private func currentErrors() -> [String] {
        var errors = runErrors
        errors.append(contentsOf: preflightIssues.filter { $0.severity == .error }.map(\.message))
        if let copyError {
            errors.append(copyError)
        }
        return Array(Set(errors)).sorted()
    }

    private func currentReportSummary() -> IngestReportSummary {
        IngestReportSummary(
            totalScannedFiles: scanResult.fileCount,
            copiedFiles: copiedFilesCount,
            verifiedFiles: verifiedFilesCount,
            skippedFiles: skippedFilesCount,
            failedFiles: failedFilesCount,
            mismatches: mismatchesCount,
            elapsedTime: elapsedTime,
            startedAt: ingestStartedAt,
            finishedAt: Date()
        )
    }

    private func writeReport(
        metadata: IngestJobMetadata,
        settings: IngestJobSettings,
        sourceURL: URL?,
        destinationURL: URL,
        reportWriter: IngestReportWriter
    ) {
        guard settings.createReport else {
            reportFiles = nil
            reportError = nil
            return
        }
        do {
            reportFiles = try reportWriter.writeReport(
                preferredReportRootURL: reportDestinationURL,
                destinationURL: destinationURL,
                jobStatus: jobStatus ?? .failed,
                metadata: metadata,
                settings: settings,
                sourceURL: sourceURL,
                summary: currentReportSummary(),
                fileResults: copyResult?.verificationRecords ?? currentRunRecords,
                warnings: currentWarnings(),
                errors: currentErrors()
            )
            reportError = nil
        } catch {
            reportError = error.localizedDescription
            if workflowState == .completed {
                workflowState = .completedWithWarnings
            }
            lastMeaningfulError = error.localizedDescription
        }
    }

    private func configuredFolderPanel(title: String, initialURL: URL?) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = initialURL
        return panel
    }

    private func availableCapacity(for destinationURL: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey
        ]

        var resourceCandidate: Int64?
        var isLocalVolume = true

        if let values = try? destinationURL.resourceValues(forKeys: keys) {
            isLocalVolume = values.volumeIsLocal ?? true

            if let importantValue = values.volumeAvailableCapacityForImportantUsage {
                let important = Int64(importantValue)
                if important > 0 { return important }
                resourceCandidate = important
            }

            if let availableValue = values.volumeAvailableCapacity {
                let available = Int64(availableValue)
                if available > 0 { return available }
                resourceCandidate = resourceCandidate ?? available
            }
        }

        if let existingPath = nearestExistingFilesystemPath(for: destinationURL) {
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: existingPath.path),
               let freeSize = attrs[.systemFreeSize] as? NSNumber {
                let candidate = freeSize.int64Value
                if candidate > 0 { return candidate }
                resourceCandidate = resourceCandidate ?? candidate
            }

            var stats = statfs()
            if existingPath.withUnsafeFileSystemRepresentation({ fsRep in
                guard let fsRep else { return false }
                return statfs(fsRep, &stats) == 0
            }) {
                let candidate = Int64(stats.f_bavail) * Int64(stats.f_bsize)
                if candidate > 0 { return candidate }
                resourceCandidate = resourceCandidate ?? candidate
            }
        }

        if isLocalVolume {
            return resourceCandidate
        }

        return resourceCandidate == 0 ? nil : resourceCandidate
    }

    private func nearestExistingFilesystemPath(for url: URL) -> URL? {
        let fileManager = FileManager.default
        var candidate = url.standardizedFileURL

        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }

        return candidate
    }

    private func restorePersistedSelections() {
        sourceURL = restoredURL(forKey: PersistedPathKey.source)
        destinationURL = restoredURL(forKey: PersistedPathKey.destination)
        reportDestinationURL = restoredURL(forKey: PersistedPathKey.reportDestination)
    }

    private func restoredURL(forKey key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return url
    }

    private func setSourceURL(_ url: URL?) {
        sourceURL = url?.standardizedFileURL
        persist(url: sourceURL, forKey: PersistedPathKey.source)
    }

    private func setDestinationURL(_ url: URL?) {
        destinationURL = url?.standardizedFileURL
        persist(url: destinationURL, forKey: PersistedPathKey.destination)
    }

    private func setReportDestinationURL(_ url: URL?) {
        reportDestinationURL = url?.standardizedFileURL
        persist(url: reportDestinationURL, forKey: PersistedPathKey.reportDestination)
    }

    private func persist(url: URL?, forKey key: String) {
        if let url {
            UserDefaults.standard.set(url.path, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
