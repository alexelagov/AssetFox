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
        try await scan(sourceURLs: [sourceURL], progress: progress)
    }

    func scan(
        sourceURLs: [URL],
        progress: (@Sendable (IngestSourceScanResult) async -> Void)? = nil
    ) async throws -> IngestSourceScanResult {
        try await scanSynchronously(sourceURLs: sourceURLs, progress: progress)
    }

    private func scanSynchronously(
        sourceURLs: [URL],
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

        var warnings: [String] = []
        var result = IngestSourceScanResult(
            fileCount: 0,
            folderCount: 0,
            totalBytes: 0,
            warnings: [],
            lastScannedPath: nil
        )
        var itemsSinceProgress = 0

        for sourceURL in sourceURLs {
            try Task.checkCancellation()

            let values: URLResourceValues
            do {
                values = try sourceURL.resourceValues(forKeys: resourceKeys)
            } catch {
                warnings.append("Could not inspect \(sourceURL.path): \(error.localizedDescription)")
                result.warnings = warnings
                continue
            }

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileNoSuchFileError,
                    userInfo: [NSLocalizedDescriptionKey: "A selected source is no longer available: \(sourceURL.path)"]
                )
            }

            if values.isReadable == false {
                warnings.append("Unreadable source item skipped: \(sourceURL.path)")
                result.warnings = warnings
                continue
            }

            if values.isRegularFile == true {
                result.fileCount += 1
                result.totalBytes += Int64(sizeOnDisk(from: values))
                result.lastScannedPath = sourceURL.path
                itemsSinceProgress += 1
                result.warnings = warnings
                if itemsSinceProgress >= 50 {
                    itemsSinceProgress = 0
                    await progress?(result)
                }
                continue
            }

            guard values.isDirectory == true else { continue }
            result.folderCount += 1

            guard let enumerator = fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    warnings.append("Could not read \(url.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                warnings.append("Could not enumerate selected source: \(sourceURL.path)")
                result.warnings = warnings
                continue
            }

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
                    result.totalBytes += Int64(sizeOnDisk(from: values))
                }

                itemsSinceProgress += 1
                result.warnings = warnings

                if itemsSinceProgress >= 50 {
                    itemsSinceProgress = 0
                    await progress?(result)
                }
            }
        }

        result.warnings = warnings
        await progress?(result)

        return result
    }

    private func sizeOnDisk(from values: URLResourceValues) -> Int {
        values.totalFileAllocatedSize
            ?? values.fileAllocatedSize
            ?? values.fileSize
            ?? 0
    }
}
