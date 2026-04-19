import CryptoKit
import Darwin
import Foundation

enum IngestConflictMode: String, CaseIterable, Identifiable {
    case skipExisting = "Skip Existing"
    case overwriteExisting = "Overwrite Existing"

    var id: String { rawValue }
}

enum IngestRunPhase {
    case idle
    case copying
    case verifying
    case completed
}

enum IngestFileVerificationState {
    case verified
    case copiedWithoutVerification
    case mismatch
    case failed(reason: String)
    case skippedExisting
}

struct IngestFileVerificationRecord: Identifiable {
    let id = UUID()
    let relativePath: String
    let sourcePath: String
    let destinationPath: String
    let fileSize: Int64
    let state: IngestFileVerificationState
}

struct IngestCopyProgress {
    var copiedFiles: Int
    var totalFiles: Int
    var copiedBytes: Int64
    var totalBytes: Int64
    var verifiedFiles: Int
    var mismatchCount: Int
    var verificationFailureCount: Int
    var currentFilePath: String?
    var phase: IngestRunPhase
    var detail: String?
    var latestRecord: IngestFileVerificationRecord?
    var warnings: [String]
    var errors: [String]

    static let idle = IngestCopyProgress(
        copiedFiles: 0,
        totalFiles: 0,
        copiedBytes: 0,
        totalBytes: 0,
        verifiedFiles: 0,
        mismatchCount: 0,
        verificationFailureCount: 0,
        currentFilePath: nil,
        phase: .idle,
        detail: nil,
        latestRecord: nil,
        warnings: [],
        errors: []
    )
}

struct IngestCopyResult {
    var copiedFiles: Int
    var skippedFiles: Int
    var totalFiles: Int
    var copiedBytes: Int64
    var totalBytes: Int64
    var destinationURL: URL
    var verificationRecords: [IngestFileVerificationRecord]
    var verifiedFiles: Int
    var mismatchCount: Int
    var verificationFailureCount: Int
    var elapsedTime: TimeInterval
    var warnings: [String]
    var errors: [String]
}

struct IngestPartialRunSnapshot {
    var copiedFiles: Int
    var skippedFiles: Int
    var totalFiles: Int
    var copiedBytes: Int64
    var totalBytes: Int64
    var verifiedFiles: Int
    var mismatchCount: Int
    var verificationFailureCount: Int
    var records: [IngestFileVerificationRecord]
    var warnings: [String]
    var errors: [String]
    var currentFilePath: String?
    var phase: IngestRunPhase
}

struct IngestCopier {
    func copyRecursively(
        sourceURL: URL,
        destinationURL: URL,
        conflictMode: IngestConflictMode,
        verificationEnabled: Bool,
        preserveFolderStructure: Bool,
        progress: @escaping @Sendable (IngestCopyProgress) async -> Void
    ) async throws -> IngestCopyResult {
        try await copySynchronously(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            conflictMode: conflictMode,
            verificationEnabled: verificationEnabled,
            preserveFolderStructure: preserveFolderStructure,
            progress: progress
        )
    }

    private func copySynchronously(
        sourceURL: URL,
        destinationURL: URL,
        conflictMode: IngestConflictMode,
        verificationEnabled: Bool,
        preserveFolderStructure: Bool,
        progress: @escaping @Sendable (IngestCopyProgress) async -> Void
    ) async throws -> IngestCopyResult {
        let fileManager = FileManager.default
        let startedAt = Date()
        let preparation = try buildCopyJobs(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            preserveFolderStructure: preserveFolderStructure
        )
        let jobs = preparation.jobs

        let totalFiles = jobs.count
        let totalBytes = jobs.reduce(into: Int64.zero) { partialResult, job in
            partialResult += job.size
        }

        var copiedFiles = 0
        var skippedFiles = 0
        var copiedBytes: Int64 = 0
        var verifiedFiles = 0
        var mismatchCount = 0
        var verificationFailureCount = preparation.initialFailureCount
        var verificationRecords = preparation.initialRecords
        var warnings = preparation.warnings
        var errors = preparation.errors

        await progress(IngestCopyProgress(
            copiedFiles: 0,
            totalFiles: totalFiles,
            copiedBytes: 0,
            totalBytes: totalBytes,
            verifiedFiles: 0,
            mismatchCount: 0,
            verificationFailureCount: verificationFailureCount,
            currentFilePath: nil,
            phase: .idle,
            detail: "Preparing ingest run",
            latestRecord: verificationRecords.last,
            warnings: warnings,
            errors: errors
        ))

        do {
            for job in jobs {
                try Task.checkCancellation()
                try ensureSourceRootAvailable(sourceURL)
                try ensureDestinationRootAvailable(destinationURL)

                let parentDirectory = job.destinationURL.deletingLastPathComponent()
                do {
                    try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    throw IngestFatalJobError.destinationUnavailable("Could not prepare destination folder for \(job.relativePath): \(error.localizedDescription)")
                }

                let destinationExists = fileManager.fileExists(atPath: job.destinationURL.path)
                if destinationExists {
                    await progress(buildProgress(
                        copiedFiles: copiedFiles,
                        totalFiles: totalFiles,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes,
                        verifiedFiles: verifiedFiles,
                        mismatchCount: mismatchCount,
                        verificationFailureCount: verificationFailureCount,
                        currentFilePath: job.relativePath,
                        phase: .copying,
                        detail: "Comparing existing destination file",
                        latestRecord: nil,
                        warnings: warnings,
                        errors: errors
                    ))

                    do {
                        let sourceHash = try sha256Hex(for: job.sourceURL)
                        let destinationHash = try sha256Hex(for: job.destinationURL)

                        if sourceHash == destinationHash {
                            skippedFiles += 1
                            let record = IngestFileVerificationRecord(
                                relativePath: job.relativePath,
                                sourcePath: job.sourceURL.path,
                                destinationPath: job.destinationURL.path,
                                fileSize: job.size,
                                state: .skippedExisting
                            )
                            verificationRecords.append(record)
                            warnings.append("Skipped existing destination file after checksum match: \(job.relativePath)")
                            await progress(buildProgress(
                                copiedFiles: copiedFiles,
                                totalFiles: totalFiles,
                                copiedBytes: copiedBytes,
                                totalBytes: totalBytes,
                                verifiedFiles: verifiedFiles,
                                mismatchCount: mismatchCount,
                                verificationFailureCount: verificationFailureCount,
                                currentFilePath: job.relativePath,
                                phase: .copying,
                                detail: "Existing file already matches source",
                                latestRecord: record,
                                warnings: warnings,
                                errors: errors
                            ))
                            continue
                        }

                        switch conflictMode {
                        case .skipExisting:
                            let message = "Destination file differs from source checksum and was not overwritten: \(job.relativePath)"
                            let record = IngestFileVerificationRecord(
                                relativePath: job.relativePath,
                                sourcePath: job.sourceURL.path,
                                destinationPath: job.destinationURL.path,
                                fileSize: job.size,
                                state: .failed(reason: message)
                            )
                            verificationRecords.append(record)
                            verificationFailureCount += 1
                            warnings.append(message)
                            await progress(buildProgress(
                                copiedFiles: copiedFiles,
                                totalFiles: totalFiles,
                                copiedBytes: copiedBytes,
                                totalBytes: totalBytes,
                                verifiedFiles: verifiedFiles,
                                mismatchCount: mismatchCount,
                                verificationFailureCount: verificationFailureCount,
                                currentFilePath: job.relativePath,
                                phase: .copying,
                                detail: message,
                                latestRecord: record,
                                warnings: warnings,
                                errors: errors
                            ))
                            continue
                        case .overwriteExisting:
                            warnings.append("Replacing destination file after checksum mismatch: \(job.relativePath)")
                            do {
                                try fileManager.removeItem(at: job.destinationURL)
                            } catch {
                                throw IngestFatalJobError.destinationUnavailable("Could not overwrite existing destination file for \(job.relativePath): \(error.localizedDescription)")
                            }
                        }
                    } catch {
                        let message = "Could not compare existing destination file for \(job.relativePath): \(error.localizedDescription)"

                        switch conflictMode {
                        case .skipExisting:
                            let record = IngestFileVerificationRecord(
                                relativePath: job.relativePath,
                                sourcePath: job.sourceURL.path,
                                destinationPath: job.destinationURL.path,
                                fileSize: job.size,
                                state: .failed(reason: message)
                            )
                            verificationRecords.append(record)
                            verificationFailureCount += 1
                            errors.append(message)
                            await progress(buildProgress(
                                copiedFiles: copiedFiles,
                                totalFiles: totalFiles,
                                copiedBytes: copiedBytes,
                                totalBytes: totalBytes,
                                verifiedFiles: verifiedFiles,
                                mismatchCount: mismatchCount,
                                verificationFailureCount: verificationFailureCount,
                                currentFilePath: job.relativePath,
                                phase: .copying,
                                detail: message,
                                latestRecord: record,
                                warnings: warnings,
                                errors: errors
                            ))
                            continue
                        case .overwriteExisting:
                            warnings.append(message)
                            do {
                                try fileManager.removeItem(at: job.destinationURL)
                            } catch {
                                throw IngestFatalJobError.destinationUnavailable("Could not overwrite existing destination file for \(job.relativePath): \(error.localizedDescription)")
                            }
                        }
                    }
                }

                if let availableBytes = availableCapacity(for: destinationURL), availableBytes < job.size {
                    throw IngestFatalJobError.insufficientDiskSpace("The destination ran out of free space while copying \(job.relativePath).")
                }

                await progress(buildProgress(
                    copiedFiles: copiedFiles,
                    totalFiles: totalFiles,
                    copiedBytes: copiedBytes,
                    totalBytes: totalBytes,
                    verifiedFiles: verifiedFiles,
                    mismatchCount: mismatchCount,
                    verificationFailureCount: verificationFailureCount,
                    currentFilePath: job.relativePath,
                    phase: .copying,
                    detail: "Copying file",
                    latestRecord: nil,
                    warnings: warnings,
                    errors: errors
                ))

                do {
                    try fileManager.copyItem(at: job.sourceURL, to: job.destinationURL)
                    copiedFiles += 1
                    copiedBytes += job.size
                } catch {
                    let message = "Copy failed for \(job.relativePath): \(error.localizedDescription)"
                    let record = IngestFileVerificationRecord(
                        relativePath: job.relativePath,
                        sourcePath: job.sourceURL.path,
                        destinationPath: job.destinationURL.path,
                        fileSize: job.size,
                        state: .failed(reason: message)
                    )
                    verificationRecords.append(record)
                    verificationFailureCount += 1
                    errors.append(message)

                    if isFatalDestinationError(error) {
                        throw IngestFatalJobError.destinationUnavailable(message)
                    }
                    if isFatalSourceError(error) {
                        throw IngestFatalJobError.sourceUnavailable(message)
                    }

                    await progress(buildProgress(
                        copiedFiles: copiedFiles,
                        totalFiles: totalFiles,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes,
                        verifiedFiles: verifiedFiles,
                        mismatchCount: mismatchCount,
                        verificationFailureCount: verificationFailureCount,
                        currentFilePath: job.relativePath,
                        phase: .copying,
                        detail: message,
                        latestRecord: record,
                        warnings: warnings,
                        errors: errors
                    ))
                    continue
                }

                guard verificationEnabled else {
                    let record = IngestFileVerificationRecord(
                        relativePath: job.relativePath,
                        sourcePath: job.sourceURL.path,
                        destinationPath: job.destinationURL.path,
                        fileSize: job.size,
                        state: .copiedWithoutVerification
                    )
                    verificationRecords.append(record)

                    await progress(buildProgress(
                        copiedFiles: copiedFiles,
                        totalFiles: totalFiles,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes,
                        verifiedFiles: verifiedFiles,
                        mismatchCount: mismatchCount,
                        verificationFailureCount: verificationFailureCount,
                        currentFilePath: job.relativePath,
                        phase: .copying,
                        detail: "Copied without post-copy verification",
                        latestRecord: record,
                        warnings: warnings,
                        errors: errors
                    ))
                    continue
                }

                await progress(buildProgress(
                    copiedFiles: copiedFiles,
                    totalFiles: totalFiles,
                    copiedBytes: copiedBytes,
                    totalBytes: totalBytes,
                    verifiedFiles: verifiedFiles,
                    mismatchCount: mismatchCount,
                    verificationFailureCount: verificationFailureCount,
                    currentFilePath: job.relativePath,
                    phase: .verifying,
                    detail: "Verifying SHA-256",
                    latestRecord: nil,
                    warnings: warnings,
                    errors: errors
                ))

                do {
                    let sourceHash = try sha256Hex(for: job.sourceURL)
                    let destinationHash = try sha256Hex(for: job.destinationURL)

                    let record: IngestFileVerificationRecord
                    if sourceHash == destinationHash {
                        verifiedFiles += 1
                        record = IngestFileVerificationRecord(
                            relativePath: job.relativePath,
                            sourcePath: job.sourceURL.path,
                            destinationPath: job.destinationURL.path,
                            fileSize: job.size,
                            state: .verified
                        )
                    } else {
                        mismatchCount += 1
                        let message = "SHA-256 mismatch detected for \(job.relativePath)"
                        warnings.append(message)
                        record = IngestFileVerificationRecord(
                            relativePath: job.relativePath,
                            sourcePath: job.sourceURL.path,
                            destinationPath: job.destinationURL.path,
                            fileSize: job.size,
                            state: .mismatch
                        )
                    }

                    verificationRecords.append(record)
                    await progress(buildProgress(
                        copiedFiles: copiedFiles,
                        totalFiles: totalFiles,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes,
                        verifiedFiles: verifiedFiles,
                        mismatchCount: mismatchCount,
                        verificationFailureCount: verificationFailureCount,
                        currentFilePath: job.relativePath,
                        phase: .verifying,
                        detail: {
                            switch record.state {
                            case .verified:
                                return "Verification passed"
                            case .copiedWithoutVerification:
                                return "Copied without post-copy verification"
                            case .mismatch, .failed, .skippedExisting:
                                return "Verification issue detected"
                            }
                        }(),
                        latestRecord: record,
                        warnings: warnings,
                        errors: errors
                    ))
                } catch {
                    let message = "Verification failed for \(job.relativePath): \(error.localizedDescription)"
                    let record = IngestFileVerificationRecord(
                        relativePath: job.relativePath,
                        sourcePath: job.sourceURL.path,
                        destinationPath: job.destinationURL.path,
                        fileSize: job.size,
                        state: .failed(reason: message)
                    )
                    verificationRecords.append(record)
                    verificationFailureCount += 1
                    errors.append(message)

                    if isFatalSourceError(error) {
                        throw IngestFatalJobError.sourceUnavailable(message)
                    }
                    if isFatalDestinationError(error) {
                        throw IngestFatalJobError.destinationUnavailable(message)
                    }

                    await progress(buildProgress(
                        copiedFiles: copiedFiles,
                        totalFiles: totalFiles,
                        copiedBytes: copiedBytes,
                        totalBytes: totalBytes,
                        verifiedFiles: verifiedFiles,
                        mismatchCount: mismatchCount,
                        verificationFailureCount: verificationFailureCount,
                        currentFilePath: job.relativePath,
                        phase: .verifying,
                        detail: message,
                        latestRecord: record,
                        warnings: warnings,
                        errors: errors
                    ))
                }
            }
        } catch let fatalError as IngestFatalJobError {
            throw fatalError.asNSError(snapshot: IngestPartialRunSnapshot(
                copiedFiles: copiedFiles,
                skippedFiles: skippedFiles,
                totalFiles: totalFiles,
                copiedBytes: copiedBytes,
                totalBytes: totalBytes,
                verifiedFiles: verifiedFiles,
                mismatchCount: mismatchCount,
                verificationFailureCount: verificationFailureCount,
                records: verificationRecords,
                warnings: warnings,
                errors: errors,
                currentFilePath: nil,
                phase: .completed
            ))
        }

        return IngestCopyResult(
            copiedFiles: copiedFiles,
            skippedFiles: skippedFiles,
            totalFiles: totalFiles,
            copiedBytes: copiedBytes,
            totalBytes: totalBytes,
            destinationURL: destinationURL,
            verificationRecords: verificationRecords,
            verifiedFiles: verifiedFiles,
            mismatchCount: mismatchCount,
            verificationFailureCount: verificationFailureCount,
            elapsedTime: Date().timeIntervalSince(startedAt),
            warnings: warnings,
            errors: errors
        )
    }

    private func buildCopyJobs(
        sourceURL: URL,
        destinationURL: URL,
        preserveFolderStructure: Bool
    ) throws -> IngestCopyPreparation {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isReadableKey
        ]

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw IngestFatalJobError.sourceUnavailable("The source is no longer available.")
        }

        var warnings: [String] = []
        var errors: [String] = []
        var initialRecords: [IngestFileVerificationRecord] = []

        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                let message = "Could not enumerate \(url.path): \(error.localizedDescription)"
                warnings.append(message)
                return true
            }
        ) else {
            throw IngestFatalJobError.sourceUnavailable("The source could not be enumerated.")
        }

        var jobs: [IngestCopyJob] = []
        let sourcePath = sourceURL.standardizedFileURL.path
        var reservedDestinationPaths = Set<String>()

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let relativePath = relativePath(for: fileURL, under: sourcePath)
            let destinationFileURL: URL
            if preserveFolderStructure {
                destinationFileURL = destinationURL.appendingPathComponent(relativePath)
            } else {
                destinationFileURL = uniqueFlatDestinationURL(
                    for: fileURL,
                    destinationRootURL: destinationURL,
                    reservedDestinationPaths: &reservedDestinationPaths
                )
            }

            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: resourceKeys)
            } catch {
                let message = "Could not inspect \(relativePath): \(error.localizedDescription)"
                errors.append(message)
                initialRecords.append(IngestFileVerificationRecord(
                    relativePath: relativePath,
                    sourcePath: fileURL.path,
                    destinationPath: destinationFileURL.path,
                    fileSize: 0,
                    state: .failed(reason: message)
                ))
                continue
            }

            guard values.isRegularFile == true else { continue }

            if values.isReadable == false {
                let message = "Unreadable source file skipped: \(relativePath)"
                errors.append(message)
                initialRecords.append(IngestFileVerificationRecord(
                    relativePath: relativePath,
                    sourcePath: fileURL.path,
                    destinationPath: destinationFileURL.path,
                    fileSize: 0,
                    state: .failed(reason: message)
                ))
                continue
            }

            let size = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0

            jobs.append(IngestCopyJob(
                sourceURL: fileURL,
                destinationURL: destinationFileURL,
                relativePath: relativePath,
                size: Int64(size)
            ))

            reservedDestinationPaths.insert(destinationFileURL.standardizedFileURL.path)
        }

        return IngestCopyPreparation(
            jobs: jobs,
            initialRecords: initialRecords,
            initialFailureCount: initialRecords.count,
            warnings: warnings,
            errors: errors
        )
    }

    private func relativePath(for fileURL: URL, under sourcePath: String) -> String {
        let fullPath = fileURL.standardizedFileURL.path
        guard fullPath.hasPrefix(sourcePath) else {
            return fileURL.lastPathComponent
        }

        let startIndex = fullPath.index(fullPath.startIndex, offsetBy: sourcePath.count)
        let suffix = String(fullPath[startIndex...])
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func uniqueFlatDestinationURL(
        for fileURL: URL,
        destinationRootURL: URL,
        reservedDestinationPaths: inout Set<String>
    ) -> URL {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        func candidateURL(_ suffix: Int?) -> URL {
            let fileName: String
            if let suffix {
                let numberedBase = "\(baseName) \(suffix)"
                fileName = fileExtension.isEmpty ? numberedBase : "\(numberedBase).\(fileExtension)"
            } else {
                fileName = fileURL.lastPathComponent
            }
            return destinationRootURL.appendingPathComponent(fileName)
        }

        var candidate = candidateURL(nil)
        var suffix = 2
        while reservedDestinationPaths.contains(candidate.standardizedFileURL.path) {
            candidate = candidateURL(suffix)
            suffix += 1
        }
        return candidate
    }

    private func ensureSourceRootAvailable(_ sourceURL: URL) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw IngestFatalJobError.sourceUnavailable("The source became unavailable during ingest.")
        }
    }

    private func ensureDestinationRootAvailable(_ destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw IngestFatalJobError.destinationUnavailable("The destination became unavailable during ingest.")
        }

        guard fileManager.isWritableFile(atPath: destinationURL.path) else {
            throw IngestFatalJobError.destinationUnavailable("The destination is no longer writable.")
        }
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

    private func buildProgress(
        copiedFiles: Int,
        totalFiles: Int,
        copiedBytes: Int64,
        totalBytes: Int64,
        verifiedFiles: Int,
        mismatchCount: Int,
        verificationFailureCount: Int,
        currentFilePath: String?,
        phase: IngestRunPhase,
        detail: String?,
        latestRecord: IngestFileVerificationRecord?,
        warnings: [String],
        errors: [String]
    ) -> IngestCopyProgress {
        IngestCopyProgress(
            copiedFiles: copiedFiles,
            totalFiles: totalFiles,
            copiedBytes: copiedBytes,
            totalBytes: totalBytes,
            verifiedFiles: verifiedFiles,
            mismatchCount: mismatchCount,
            verificationFailureCount: verificationFailureCount,
            currentFilePath: currentFilePath,
            phase: phase,
            detail: detail,
            latestRecord: latestRecord,
            warnings: warnings,
            errors: errors
        )
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()

            let chunk = try autoreleasepool {
                try handle.read(upToCount: 1024 * 1024) ?? Data()
            }

            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isFatalDestinationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let fatalCodes = [NSFileWriteNoPermissionError, NSFileWriteOutOfSpaceError, NSFileWriteUnknownError]
        return nsError.domain == NSCocoaErrorDomain && fatalCodes.contains(nsError.code)
    }

    private func isFatalSourceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let fatalCodes = [NSFileReadNoSuchFileError, NSFileReadNoPermissionError, NSFileReadUnknownError]
        return nsError.domain == NSCocoaErrorDomain && fatalCodes.contains(nsError.code)
    }
}

private struct IngestCopyJob {
    let sourceURL: URL
    let destinationURL: URL
    let relativePath: String
    let size: Int64
}

private struct IngestCopyPreparation {
    let jobs: [IngestCopyJob]
    let initialRecords: [IngestFileVerificationRecord]
    let initialFailureCount: Int
    let warnings: [String]
    let errors: [String]
}

private enum IngestFatalJobError: Error {
    case sourceUnavailable(String)
    case destinationUnavailable(String)
    case insufficientDiskSpace(String)

    func asNSError(snapshot: IngestPartialRunSnapshot) -> NSError {
        let description: String
        switch self {
        case .sourceUnavailable(let message), .destinationUnavailable(let message), .insufficientDiskSpace(let message):
            description = message
        }

        return NSError(
            domain: "AssetFox.Ingest",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: description,
                "partialSnapshot": snapshot
            ]
        )
    }
}
