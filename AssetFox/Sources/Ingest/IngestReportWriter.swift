import Foundation

struct IngestJobMetadata {
    let jobName: String
    let reelName: String
    let priority: String
}

struct IngestJobSettings {
    let conflictMode: String
    let checksumVerification: String
    let preserveFolderStructure: Bool
    let createReport: Bool
    let requestedReportRootPath: String?
}

struct IngestReportFiles {
    let directoryURL: URL
    let jsonURL: URL
    let csvURL: URL
    let textURL: URL
}

struct IngestReportWriter {
    func writeReport(
        preferredReportRootURL: URL?,
        destinationURL: URL,
        jobStatus: IngestJobStatus,
        metadata: IngestJobMetadata,
        settings: IngestJobSettings,
        sourceURL: URL?,
        summary: IngestReportSummary,
        fileResults: [IngestFileVerificationRecord],
        warnings: [String],
        errors: [String]
    ) throws -> IngestReportFiles {
        let reportsDirectory = try resolveReportsDirectory(
            preferredReportRootURL: preferredReportRootURL,
            preferredDestinationURL: destinationURL
        )
        let jobDirectory = reportsDirectory.appendingPathComponent(reportFolderName(for: metadata), isDirectory: true)

        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true, attributes: nil)

        let jsonURL = jobDirectory.appendingPathComponent("ingest-report.json")
        let csvURL = jobDirectory.appendingPathComponent("ingest-files.csv")
        let textURL = jobDirectory.appendingPathComponent("ingest-summary.txt")

        let payload = CodableIngestReport(
            generatedAt: summary.finishedAt?.ISO8601Format() ?? Date().ISO8601Format(),
            status: jobStatus.rawValue,
            jobMetadata: .init(
                jobName: metadata.jobName,
                reelName: metadata.reelName,
                priority: metadata.priority
            ),
            sourcePath: sourceURL?.path,
            destinationPath: destinationURL.path,
            requestedReportRootPath: preferredReportRootURL?.path,
            reportDirectoryPath: jobDirectory.path,
            reportFiles: .init(
                jsonPath: jsonURL.path,
                csvPath: csvURL.path,
                textPath: textURL.path
            ),
            settings: .init(
                conflictMode: settings.conflictMode,
                checksumVerification: settings.checksumVerification,
                preserveFolderStructure: settings.preserveFolderStructure,
                createReport: settings.createReport,
                requestedReportRootPath: settings.requestedReportRootPath
            ),
            timing: .init(
                startedAt: summary.startedAt?.ISO8601Format(),
                finishedAt: summary.finishedAt?.ISO8601Format(),
                elapsedSeconds: summary.elapsedTime
            ),
            summaryCounts: .init(
                totalScannedFiles: summary.totalScannedFiles,
                copiedFiles: summary.copiedFiles,
                verifiedFiles: summary.verifiedFiles,
                skippedFiles: summary.skippedFiles,
                failedFiles: summary.failedFiles,
                mismatches: summary.mismatches
            ),
            fileResults: fileResults.map {
                .init(
                    relativePath: $0.relativePath,
                    sourcePath: $0.sourcePath,
                    destinationPath: $0.destinationPath,
                    fileSize: $0.fileSize,
                    status: reportStatus(for: $0.state),
                    detail: reportDetail(for: $0.state)
                )
            },
            warnings: warnings,
            errors: errors
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: jsonURL, options: .atomic)

        let csv = buildCSV(fileResults: fileResults)
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        let text = buildTextSummary(
            status: jobStatus,
            metadata: metadata,
            settings: settings,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            reportDirectoryURL: jobDirectory,
            csvURL: csvURL,
            jsonURL: jsonURL,
            textURL: textURL,
            summary: summary,
            fileResults: fileResults,
            warnings: warnings,
            errors: errors
        )
        try text.write(to: textURL, atomically: true, encoding: .utf8)

        return IngestReportFiles(
            directoryURL: jobDirectory,
            jsonURL: jsonURL,
            csvURL: csvURL,
            textURL: textURL
        )
    }

    private func resolveReportsDirectory(preferredReportRootURL: URL?, preferredDestinationURL: URL) throws -> URL {
        let fileManager = FileManager.default

        if let preferredReportRootURL,
           fileManager.fileExists(atPath: preferredReportRootURL.path),
           fileManager.isWritableFile(atPath: preferredReportRootURL.path) {
            return preferredReportRootURL
        }

        if fileManager.fileExists(atPath: preferredDestinationURL.path),
           fileManager.isWritableFile(atPath: preferredDestinationURL.path) {
            return preferredDestinationURL.appendingPathComponent("_ASSETFOX_INGEST_REPORTS", isDirectory: true)
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fallback = applicationSupport
            .appendingPathComponent("AssetFox", isDirectory: true)
            .appendingPathComponent("IngestReports", isDirectory: true)
        try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true, attributes: nil)
        return fallback
    }

    private func reportFolderName(for metadata: IngestJobMetadata) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let slug = metadata.jobName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let name = slug.isEmpty ? "ingest-job" : slug
        return "\(timestamp)-\(name)"
    }

    private func reportStatus(for state: IngestFileVerificationState) -> String {
        switch state {
        case .verified:
            return "verified"
        case .copiedWithoutVerification:
            return "copied_unverified"
        case .mismatch:
            return "mismatch"
        case .failed:
            return "failed"
        case .skippedExisting:
            return "skipped_existing"
        }
    }

    private func reportDetail(for state: IngestFileVerificationState) -> String? {
        switch state {
        case .verified, .copiedWithoutVerification, .mismatch, .skippedExisting:
            return nil
        case .failed(let reason):
            return reason
        }
    }

    private func buildCSV(fileResults: [IngestFileVerificationRecord]) -> String {
        let header = [
            "relative_path",
            "source_path",
            "destination_path",
            "file_size_bytes",
            "status",
            "detail"
        ]

        let rows = fileResults.map { record in
            [
                record.relativePath,
                record.sourcePath,
                record.destinationPath,
                String(record.fileSize),
                reportStatus(for: record.state),
                reportDetail(for: record.state) ?? ""
            ]
        }

        return ([header] + rows)
            .map { row in row.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    private func buildTextSummary(
        status: IngestJobStatus,
        metadata: IngestJobMetadata,
        settings: IngestJobSettings,
        sourceURL: URL?,
        destinationURL: URL,
        reportDirectoryURL: URL,
        csvURL: URL,
        jsonURL: URL,
        textURL: URL,
        summary: IngestReportSummary,
        fileResults: [IngestFileVerificationRecord],
        warnings: [String],
        errors: [String]
    ) -> String {
        let lines: [String] = [
            "AssetFox Ingest Report",
            "",
            "Status: \(status.rawValue)",
            "Job Name: \(metadata.jobName)",
            "Reel Name: \(metadata.reelName)",
            "Priority: \(metadata.priority)",
            "Source: \(sourceURL?.path ?? "Unavailable")",
            "Destination: \(destinationURL.path)",
            "Requested Report Root: \(settings.requestedReportRootPath ?? "Destination default")",
            "Report Directory: \(reportDirectoryURL.path)",
            "CSV Report: \(csvURL.path)",
            "TXT Summary: \(textURL.path)",
            "JSON Report: \(jsonURL.path)",
            "Conflict Mode: \(settings.conflictMode)",
            "Checksum Verification: \(settings.checksumVerification)",
            "Preserve Folder Structure: \(settings.preserveFolderStructure ? "Yes" : "No")",
            "Reports Enabled: \(settings.createReport ? "Yes" : "No")",
            "Started: \(summary.startedAt?.ISO8601Format() ?? "Unavailable")",
            "Finished: \(summary.finishedAt?.ISO8601Format() ?? "Unavailable")",
            "Elapsed: \(summary.elapsedTime)s",
            "",
            "Summary Counts",
            "Scanned Files: \(summary.totalScannedFiles)",
            "Copied Files: \(summary.copiedFiles)",
            "Verified Files: \(summary.verifiedFiles)",
            "Skipped Files: \(summary.skippedFiles)",
            "Failed Files: \(summary.failedFiles)",
            "Mismatches: \(summary.mismatches)",
            "",
            "Warnings:",
        ]

        let warningLines = warnings.isEmpty ? ["- None"] : warnings.map { "- \($0)" }
        let errorHeader = ["", "Errors:"]
        let errorLines = errors.isEmpty ? ["- None"] : errors.map { "- \($0)" }
        let fileHeader = ["", "File Results:"]
        let fileLines = fileResults.isEmpty ? ["- None"] : fileResults.map { record in
            let detail = reportDetail(for: record.state).map { " (\($0))" } ?? ""
            return "- [\(reportStatus(for: record.state))] \(record.relativePath)\(detail)"
        }

        return (lines + warningLines + errorHeader + errorLines + fileHeader + fileLines).joined(separator: "\n")
    }
}

struct IngestReportSummary {
    let totalScannedFiles: Int
    let copiedFiles: Int
    let verifiedFiles: Int
    let skippedFiles: Int
    let failedFiles: Int
    let mismatches: Int
    let elapsedTime: TimeInterval
    let startedAt: Date?
    let finishedAt: Date?
}

private struct CodableIngestReport: Codable {
    let generatedAt: String
    let status: String
    let jobMetadata: CodableJobMetadata
    let sourcePath: String?
    let destinationPath: String
    let requestedReportRootPath: String?
    let reportDirectoryPath: String
    let reportFiles: CodableReportFiles
    let settings: CodableSettings
    let timing: CodableTiming
    let summaryCounts: CodableSummaryCounts
    let fileResults: [CodableFileResult]
    let warnings: [String]
    let errors: [String]

    struct CodableJobMetadata: Codable {
        let jobName: String
        let reelName: String
        let priority: String
    }

    struct CodableSettings: Codable {
        let conflictMode: String
        let checksumVerification: String
        let preserveFolderStructure: Bool
        let createReport: Bool
        let requestedReportRootPath: String?
    }

    struct CodableTiming: Codable {
        let startedAt: String?
        let finishedAt: String?
        let elapsedSeconds: TimeInterval
    }

    struct CodableReportFiles: Codable {
        let jsonPath: String
        let csvPath: String
        let textPath: String
    }

    struct CodableSummaryCounts: Codable {
        let totalScannedFiles: Int
        let copiedFiles: Int
        let verifiedFiles: Int
        let skippedFiles: Int
        let failedFiles: Int
        let mismatches: Int
    }

    struct CodableFileResult: Codable {
        let relativePath: String
        let sourcePath: String
        let destinationPath: String
        let fileSize: Int64
        let status: String
        let detail: String?
    }
}
