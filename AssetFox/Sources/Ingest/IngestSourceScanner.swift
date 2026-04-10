import Foundation

struct IngestSourceScanResult {
    var fileCount: Int
    var folderCount: Int
    var totalBytes: Int64
    var warnings: [String]
    var lastScannedPath: String?

    static let empty = IngestSourceScanResult(
        fileCount: 0,
        folderCount: 0,
        totalBytes: 0,
        warnings: [],
        lastScannedPath: nil
    )
}

struct IngestSourceScanner {
    func scan(
        sourceURL: URL,
        progress: (@Sendable (IngestSourceScanResult) async -> Void)? = nil
    ) async throws -> IngestSourceScanResult {
        try await Task.detached(priority: .userInitiated) {
            try await scanSynchronously(sourceURL: sourceURL, progress: progress)
        }.value
    }

    private func scanSynchronously(
        sourceURL: URL,
        progress: (@Sendable (IngestSourceScanResult) async -> Void)?
    ) async throws -> IngestSourceScanResult {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isReadableKey
        ]

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileNoSuchFileError,
                userInfo: [NSLocalizedDescriptionKey: "The selected source is no longer available."]
            )
        }

        var warnings: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                warnings.append("Could not read \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            return .empty
        }

        var result = IngestSourceScanResult(
            fileCount: 0,
            folderCount: 1,
            totalBytes: 0,
            warnings: [],
            lastScannedPath: nil
        )
        var itemsSinceProgress = 0

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            result.lastScannedPath = url.path

            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                warnings.append("Could not inspect \(url.path): \(error.localizedDescription)")
                result.warnings = warnings
                continue
            }

            if values.isReadable == false {
                warnings.append("Unreadable source item skipped: \(url.path)")
                result.warnings = warnings
                continue
            }

            if values.isDirectory == true {
                result.folderCount += 1
            } else if values.isRegularFile == true {
                result.fileCount += 1

                let size = values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0

                result.totalBytes += Int64(size)
            }

            itemsSinceProgress += 1
            result.warnings = warnings

            if itemsSinceProgress >= 50 {
                itemsSinceProgress = 0
                await progress?(result)
            }
        }

        result.warnings = warnings
        await progress?(result)

        return result
    }
}
