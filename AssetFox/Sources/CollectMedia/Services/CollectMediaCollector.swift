import Foundation

enum CollectMediaServiceError: LocalizedError {
    case missingXML
    case invalidXMLPath
    case missingDestination
    case invalidDestinationPath
    case invalidSearchRootPath

    var errorDescription: String? {
        switch self {
        case .missingXML:
            return "Please select an XML file."
        case .invalidXMLPath:
            return "The selected XML file does not exist."
        case .missingDestination:
            return "Please select a destination folder."
        case .invalidDestinationPath:
            return "The selected destination folder does not exist."
        case .invalidSearchRootPath:
            return "The selected search root folder does not exist."
        }
    }
}

struct CollectReportRow: Sendable {
    var sourcePath: String
    var status: String
    var destinationPath: String
    var reason: String
}

struct CollectCandidateMatch: Sendable {
    var url: URL
    var score: Int
    var reason: String
}

struct CollectRelinkResolution: Sendable {
    var resolvedURL: URL?
    var score: Int
    var reason: String
    var topCandidates: [CollectCandidateMatch]
}

typealias CollectProgressHandler = @Sendable (CollectProgress) async -> Void

struct CollectMediaCollector {
    private let relinker: CollectMediaRelinker
    private let sequenceDetector: CollectMediaSequenceDetector

    init(
        relinker: CollectMediaRelinker,
        sequenceDetector: CollectMediaSequenceDetector = CollectMediaSequenceDetector()
    ) {
        self.relinker = relinker
        self.sequenceDetector = sequenceDetector
    }

    func collect(
        entries: [CollectMediaEntry],
        parserRows: [CollectReportRow],
        request: CollectRequest,
        cancellation: CollectCancellationController,
        progress: CollectProgressHandler
    ) async throws -> CollectResult {
        let destinationURL = request.destinationURL
        let options = request.options
        let manager = FileManager.default

        var counts = CollectCounts(found: entries.count, copied: 0, missing: 0, skipped: parserRows.count)
        var reportRows = parserRows
        var missingPaths: [String] = []
        let inferredRoot = inferRoot(for: entries.map(\.sourcePath))

        if let warning = inferredRoot.warning {
            await progress(makeProgress(
                phase: .preparing,
                current: nil,
                completed: 0,
                total: entries.count,
                counts: counts,
                message: "Warning: \(warning)"
            ))
        }

        for note in parserRows {
            await progress(makeProgress(
                phase: .parsingXML,
                current: note.sourcePath,
                completed: 0,
                total: entries.count,
                counts: counts,
                message: "Skipped non-file entry: \(note.sourcePath)"
            ))
        }

        for (index, originalEntry) in entries.enumerated() {
            if await cancellation.isCancelled {
                break
            }

            var entry = originalEntry
            let originalSourceURL = URL(fileURLWithPath: entry.sourcePath)
            if entry.expectedSizeBytes == nil,
               let fileSize = try? originalSourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                entry.expectedSizeBytes = Int64(fileSize)
            }

            var effectiveSourceURL = originalSourceURL
            var itemNotes: [String] = []
            var relinkReason: String?
            let progressCount = index + 1

            if !manager.fileExists(atPath: effectiveSourceURL.path) {
                if options.smartRelink, let searchRoot = options.searchRoot {
                    await progress(makeProgress(
                        phase: .relinking,
                        current: entry.sourcePath,
                        completed: index,
                        total: entries.count,
                        counts: counts,
                        message: "Searching relink candidates for \(entry.basename)"
                    ))
                    let resolution = relinker.resolveMissing(entry: entry, searchRoot: searchRoot, options: options)
                    if let match = resolution.resolvedURL {
                        effectiveSourceURL = match
                        relinkReason = "relinked score=\(resolution.score); checks=\(resolution.reason); from=\(match.path)"
                        await progress(makeProgress(
                            phase: .relinking,
                            current: entry.sourcePath,
                            completed: index,
                            total: entries.count,
                            counts: counts,
                            message: "Relinked: \(entry.sourcePath) -> \(match.path)"
                        ))
                    } else {
                        counts.missing += 1
                        missingPaths.append(entry.sourcePath)
                        reportRows.append(CollectReportRow(
                            sourcePath: entry.sourcePath,
                            status: "unresolved",
                            destinationPath: "",
                            reason: composeReason(
                                base: unresolvedReason(from: resolution),
                                notes: itemNotes
                            )
                        ))
                        await progress(makeProgress(
                            phase: .relinking,
                            current: entry.sourcePath,
                            completed: progressCount,
                            total: entries.count,
                            counts: counts,
                            message: "Unresolved: \(entry.sourcePath)"
                        ))
                        continue
                    }
                } else {
                    counts.missing += 1
                    missingPaths.append(entry.sourcePath)
                    reportRows.append(CollectReportRow(
                        sourcePath: entry.sourcePath,
                        status: "missing",
                        destinationPath: "",
                        reason: composeReason(
                            base: "source does not exist or is not a regular file",
                            notes: itemNotes
                        )
                    ))
                    await progress(makeProgress(
                        phase: .copying,
                        current: entry.sourcePath,
                        completed: progressCount,
                        total: entries.count,
                        counts: counts,
                        message: "Missing: \(entry.sourcePath)"
                    ))
                    continue
                }
            }

            if let sequence = sequenceDetector.detectSequence(for: effectiveSourceURL) {
                let copied = try await copySequence(
                    sourceURL: effectiveSourceURL,
                    sequence: sequence,
                    destinationURL: destinationURL,
                    inferredRoot: inferredRoot.rootURL,
                    options: options,
                    cancellation: cancellation
                )

                itemNotes.append(contentsOf: copied.notes)
                if copied.copiedFrames > 0 {
                    counts.copied += 1
                    reportRows.append(CollectReportRow(
                        sourcePath: entry.sourcePath,
                        status: "sequence_copied",
                        destinationPath: copied.destinationPath,
                        reason: composeReason(
                            base: sequenceReason(
                                copiedFrames: copied.copiedFrames,
                                skippedFrames: copied.skippedFrames,
                                frameCount: copied.totalFrames,
                                relinkReason: relinkReason,
                                stopped: copied.stopped
                            ),
                            notes: itemNotes
                        )
                    ))
                    await progress(makeProgress(
                        phase: copied.stopped ? .cancelled : .copying,
                        current: entry.sourcePath,
                        completed: progressCount,
                        total: entries.count,
                        counts: counts,
                        message: "Sequence copied: \(entry.basename)"
                    ))
                } else {
                    counts.skipped += 1
                    reportRows.append(CollectReportRow(
                        sourcePath: entry.sourcePath,
                        status: "skipped",
                        destinationPath: copied.destinationPath,
                        reason: composeReason(
                            base: sequenceReason(
                                copiedFrames: copied.copiedFrames,
                                skippedFrames: copied.skippedFrames,
                                frameCount: copied.totalFrames,
                                relinkReason: relinkReason,
                                stopped: copied.stopped
                            ) + "; no frames copied",
                            notes: itemNotes
                        )
                    ))
                    await progress(makeProgress(
                        phase: copied.stopped ? .cancelled : .copying,
                        current: entry.sourcePath,
                        completed: progressCount,
                        total: entries.count,
                        counts: counts,
                        message: "Sequence skipped: \(entry.basename)"
                    ))
                }
                if copied.stopped {
                    break
                }
                continue
            }

            let targetResolution = destinationURLForSource(
                sourceURL: effectiveSourceURL,
                destinationURL: destinationURL,
                inferredRoot: inferredRoot.rootURL,
                options: options
            )
            itemNotes.append(contentsOf: targetResolution.notes)

            let copyResult = try copySingleFile(
                sourceURL: effectiveSourceURL,
                destinationURL: targetResolution.destinationURL,
                options: options
            )
            if copyResult.status == "skipped" {
                counts.skipped += 1
                reportRows.append(CollectReportRow(
                    sourcePath: entry.sourcePath,
                    status: "skipped",
                    destinationPath: copyResult.destinationURL.path,
                    reason: composeReason(base: "duplicate destination file", notes: itemNotes)
                ))
                await progress(makeProgress(
                    phase: .copying,
                    current: entry.sourcePath,
                    completed: progressCount,
                    total: entries.count,
                    counts: counts,
                    message: "Skipped duplicate: \(entry.basename)"
                ))
                continue
            }

            counts.copied += 1
            let finalStatus = relinkReason == nil ? "copied" : "relinked"
            reportRows.append(CollectReportRow(
                sourcePath: entry.sourcePath,
                status: finalStatus,
                destinationPath: copyResult.destinationURL.path,
                reason: composeReason(base: relinkReason ?? "", notes: itemNotes)
            ))
            await progress(makeProgress(
                phase: .copying,
                current: entry.sourcePath,
                completed: progressCount,
                total: entries.count,
                counts: counts,
                message: "Copied: \(entry.basename)"
            ))
        }

        let status: CollectResultStatus = await cancellation.isCancelled ? .stopped : .completed
        await progress(makeProgress(
            phase: .writingReports,
            current: nil,
            completed: entries.count,
            total: entries.count,
            counts: counts,
            message: "Writing report artifacts..."
        ))

        let reportURL = destinationURL.appendingPathComponent("report.csv")
        try writeReportCSV(rows: reportRows, to: reportURL)

        let missingURL = destinationURL.appendingPathComponent("missing.txt")
        try writeMissingList(paths: missingPaths, to: missingURL)
        let finalMissingURL: URL? = missingPaths.isEmpty ? nil : missingURL

        return CollectResult(
            counts: counts,
            destinationURL: destinationURL,
            reportCSVURL: reportURL,
            missingTextURL: finalMissingURL,
            status: status
        )
    }

    private func makeProgress(
        phase: CollectProgress.Phase,
        current: String?,
        completed: Int,
        total: Int,
        counts: CollectCounts,
        message: String
    ) -> CollectProgress {
        CollectProgress(
            phase: phase,
            completedUnitCount: completed,
            totalUnitCount: total,
            currentItem: current,
            counts: counts,
            message: message
        )
    }

    private func unresolvedReason(from resolution: CollectRelinkResolution) -> String {
        if resolution.topCandidates.isEmpty {
            return "relink unresolved (best_score=\(resolution.score), checks=\(resolution.reason), top3=none)"
        }
        let preview = resolution.topCandidates.prefix(3).map { match in
            "\(shortened(match.url.path)) (\(match.score))"
        }.joined(separator: ", ")
        return "relink unresolved (best_score=\(resolution.score), checks=\(resolution.reason), top3=\(preview))"
    }

    private func sequenceReason(
        copiedFrames: Int,
        skippedFrames: Int,
        frameCount: Int,
        relinkReason: String?,
        stopped: Bool
    ) -> String {
        var reason = "sequence frames=\(frameCount) copied=\(copiedFrames) skipped=\(skippedFrames)"
        if let relinkReason {
            reason += "; \(relinkReason)"
        }
        if stopped {
            reason += "; stopped_by_user"
        }
        return reason
    }

    private func composeReason(base: String, notes: [String]) -> String {
        let allParts = ([base] + notes).filter { !$0.isEmpty }
        return allParts.joined(separator: "; ")
    }

    private func shortened(_ path: String, maxLength: Int = 120) -> String {
        guard path.count > maxLength else { return path }
        return "..." + path.suffix(maxLength - 3)
    }

    private func writeReportCSV(rows: [CollectReportRow], to url: URL) throws {
        var lines = ["source_path,status,dest_path,reason"]
        for row in rows {
            lines.append([
                csvEscaped(row.sourcePath),
                csvEscaped(row.status),
                csvEscaped(row.destinationPath),
                csvEscaped(row.reason)
            ].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMissingList(paths: [String], to url: URL) throws {
        let contents = paths.joined(separator: "\n")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func inferRoot(for paths: [String]) -> (rootURL: URL?, warning: String?) {
        let absolutePaths = paths.filter { $0.hasPrefix("/") }
        guard !absolutePaths.isEmpty else {
            return (nil, "Could not infer common root; flatten fallback will be used for relative paths.")
        }

        var root = absolutePaths.reduce(absolutePaths[0]) { partial, next in
            commonPath(partial, next)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), !isDirectory.boolValue {
            root = URL(fileURLWithPath: root).deletingLastPathComponent().path
        }

        if root == "/" {
            return (URL(fileURLWithPath: "/"), "Common root is too broad; preserving from filesystem root (/).")
        }

        return (URL(fileURLWithPath: root), nil)
    }

    private func commonPath(_ lhs: String, _ rhs: String) -> String {
        let lhsComponents = lhs.split(separator: "/")
        let rhsComponents = rhs.split(separator: "/")
        let shared = zip(lhsComponents, rhsComponents).prefix { $0 == $1 }.map(\.0)
        return "/" + shared.joined(separator: "/")
    }

    private func destinationURLForSource(
        sourceURL: URL,
        destinationURL: URL,
        inferredRoot: URL?,
        options: CollectOptions
    ) -> (destinationURL: URL, notes: [String]) {
        guard options.preserveStructure else {
            return (destinationURL.appendingPathComponent(sourceURL.lastPathComponent), [])
        }

        switch options.preserveMode {
        case .baseRoot:
            let base = inferredRoot ?? URL(fileURLWithPath: "/")
            let relativePath = relativePathFromBase(sourceURL.path, basePath: base.path)
            return (
                destinationURL.appendingPathComponent(relativePath),
                relativePath.hasPrefix("..") ? ["used filesystem root fallback"] : []
            )
        case .tailN:
            return tailDestinationURL(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                initialTailCount: max(1, min(options.tailN, 20)),
                options: options
            )
        }
    }

    private func relativePathFromBase(_ sourcePath: String, basePath: String) -> String {
        guard basePath != "/" else {
            return sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let prefix = normalizedBase + "/"
        if sourcePath.hasPrefix(prefix) {
            return String(sourcePath.dropFirst(prefix.count))
        }
        return sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func tailDestinationURL(
        sourceURL: URL,
        destinationURL: URL,
        initialTailCount: Int,
        options: CollectOptions
    ) -> (destinationURL: URL, notes: [String]) {
        var notes = ["preserve_tail_n=\(initialTailCount)"]
        for tailCount in initialTailCount...20 {
            let relativePath = buildTailRelativePath(for: sourceURL, tailCount: tailCount)
            let candidate = destinationURL.appendingPathComponent(relativePath)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                if tailCount != initialTailCount {
                    notes = ["preserve_tail_n=\(tailCount)", "tail_n_auto_bumped:\(initialTailCount)->\(tailCount)"]
                }
                return (candidate, notes)
            }
            if options.skipDuplicates, sameFileMetadata(sourceURL, candidate) {
                if tailCount != initialTailCount {
                    notes = ["preserve_tail_n=\(tailCount)", "tail_n_auto_bumped:\(initialTailCount)->\(tailCount)"]
                }
                return (candidate, notes)
            }
        }

        let relativePath = buildTailRelativePath(for: sourceURL, tailCount: 20)
        notes = [
            "preserve_tail_n=20",
            "tail_n_auto_bumped:\(initialTailCount)->20",
            "tail_n_suffix_fallback"
        ]
        return (destinationURL.appendingPathComponent(relativePath), notes)
    }

    private func buildTailRelativePath(for sourceURL: URL, tailCount: Int) -> String {
        let components = sourceURL.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        let kept = components.suffix(max(1, tailCount))
        return (Array(kept) + [sourceURL.lastPathComponent]).joined(separator: "/")
    }

    private func sameFileMetadata(_ lhs: URL, _ rhs: URL) -> Bool {
        guard
            let lhsValues = try? lhs.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let rhsValues = try? rhs.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let lhsSize = lhsValues.fileSize,
            let rhsSize = rhsValues.fileSize,
            let lhsDate = lhsValues.contentModificationDate,
            let rhsDate = rhsValues.contentModificationDate
        else {
            return false
        }

        return lhsSize == rhsSize && Int(lhsDate.timeIntervalSince1970) == Int(rhsDate.timeIntervalSince1970)
    }

    private func copySingleFile(
        sourceURL: URL,
        destinationURL: URL,
        options: CollectOptions
    ) throws -> (status: String, destinationURL: URL) {
        let manager = FileManager.default
        try manager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var finalURL = destinationURL
        if manager.fileExists(atPath: finalURL.path) {
            if options.skipDuplicates, sameFileMetadata(sourceURL, finalURL) {
                return ("skipped", finalURL)
            }
            finalURL = uniqueDestinationURL(for: finalURL)
        }

        try manager.copyItem(at: sourceURL, to: finalURL)
        return ("copied", finalURL)
    }

    private func uniqueDestinationURL(for url: URL) -> URL {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2

        while true {
            let candidateName = ext.isEmpty ? "\(name)_\(index)" : "\(name)_\(index).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !manager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func copySequence(
        sourceURL: URL,
        sequence: SequenceMatch,
        destinationURL: URL,
        inferredRoot: URL?,
        options: CollectOptions,
        cancellation: CollectCancellationController
    ) async throws -> (destinationPath: String, copiedFrames: Int, skippedFrames: Int, totalFrames: Int, stopped: Bool, notes: [String]) {
        let frames = sequenceDetector.frames(for: sourceURL, sequence: sequence)
        var copiedFrames = 0
        var skippedFrames = 0
        var notes: [String] = []
        var finalDestinationPath = ""
        var lockedTailCount: Int?
        var stopped = false

        for frameURL in frames {
            if await cancellation.isCancelled {
                stopped = true
                break
            }

            let targetResolution: (destinationURL: URL, notes: [String])
            if options.preserveStructure {
                if options.preserveMode == .tailN, let lockedTailCount {
                    let relativePath = buildTailRelativePath(for: frameURL, tailCount: lockedTailCount)
                    targetResolution = (destinationURL.appendingPathComponent(relativePath), ["preserve_tail_n=\(lockedTailCount)"])
                } else {
                    targetResolution = destinationURLForSource(
                        sourceURL: frameURL,
                        destinationURL: destinationURL,
                        inferredRoot: inferredRoot,
                        options: options
                    )
                    if options.preserveMode == .tailN {
                        lockedTailCount = extractTailCount(from: targetResolution.notes)
                    }
                }
            } else {
                let sequenceFolder = sequenceDetector.sequenceFolderName(for: sequence)
                targetResolution = (
                    destinationURL.appendingPathComponent(sequenceFolder).appendingPathComponent(frameURL.lastPathComponent),
                    []
                )
            }

            notes.append(contentsOf: targetResolution.notes)
            let copyResult = try copySingleFile(
                sourceURL: frameURL,
                destinationURL: targetResolution.destinationURL,
                options: options
            )
            finalDestinationPath = finalDestinationPath.isEmpty
                ? copyResult.destinationURL.deletingLastPathComponent().path
                : finalDestinationPath
            if copyResult.status == "copied" {
                copiedFrames += 1
            } else {
                skippedFrames += 1
            }
        }

        return (finalDestinationPath, copiedFrames, skippedFrames, frames.count, stopped, Array(Set(notes)).sorted())
    }

    private func extractTailCount(from notes: [String]) -> Int? {
        for note in notes where note.hasPrefix("preserve_tail_n=") {
            return Int(note.replacingOccurrences(of: "preserve_tail_n=", with: ""))
        }
        return nil
    }

}
