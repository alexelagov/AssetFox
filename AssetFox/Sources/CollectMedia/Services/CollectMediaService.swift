import Foundation

struct CollectMediaService: CollectMediaRunning {
    func makeRun(request: CollectRequest) -> any CollectMediaRun {
        let xmlParser = CollectMediaXMLParser()
        let premiereProjectParser = CollectMediaPremiereProjectParser()
        let ffProbeAdapter = FFProbeAdapter()
        let relinker = CollectMediaRelinker(ffProbeAdapter: ffProbeAdapter)
        let collector = CollectMediaCollector(relinker: relinker)
        return ServiceRun(
            request: request,
            xmlParser: xmlParser,
            premiereProjectParser: premiereProjectParser,
            collector: collector,
            ffProbeAdapter: ffProbeAdapter
        )
    }
}

private final class ServiceRun: CollectMediaRun, @unchecked Sendable {
    let progress: AsyncStream<CollectProgress>

    private let continuation: AsyncStream<CollectProgress>.Continuation
    private let cancellation: CollectCancellationController
    private let task: Task<CollectResult, Error>

    init(
        request: CollectRequest,
        xmlParser: CollectMediaXMLParser,
        premiereProjectParser: CollectMediaPremiereProjectParser,
        collector: CollectMediaCollector,
        ffProbeAdapter: FFProbeAdapter
    ) {
        var streamContinuation: AsyncStream<CollectProgress>.Continuation!
        progress = AsyncStream { continuation in
            streamContinuation = continuation
        }
        let progressContinuation = streamContinuation!
        continuation = progressContinuation
        let cancellation = CollectCancellationController()
        self.cancellation = cancellation

        task = Task {
            do {
                try Self.validate(request: request)

                progressContinuation.yield(CollectProgress(
                    phase: .preparing,
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    currentItem: nil,
                    counts: CollectCounts(),
                    message: ffProbeAdapter.isAvailable
                        ? "ffprobe detected at \(ffProbeAdapter.executableURL?.path ?? "PATH")."
                        : "ffprobe not found; duration/timecode matching disabled."
                ))

                progressContinuation.yield(CollectProgress(
                    phase: .parsingXML,
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    currentItem: Self.sourceDocumentSummary(for: request),
                    counts: CollectCounts(),
                    message: "Parsing source document(s)..."
                ))

                let parsed = try Self.parseDocuments(
                    request: request,
                    xmlParser: xmlParser,
                    premiereProjectParser: premiereProjectParser
                )
                progressContinuation.yield(CollectProgress(
                    phase: .parsingXML,
                    completedUnitCount: 0,
                    totalUnitCount: parsed.entries.count,
                    currentItem: Self.sourceDocumentSummary(for: request),
                    counts: CollectCounts(found: parsed.entries.count, copied: 0, missing: 0, skipped: parsed.parserRows.count),
                    message: "Found \(parsed.entries.count) unique media item(s)."
                ))

                let result = try await collector.collect(
                    entries: parsed.entries,
                    parserRows: parsed.parserRows,
                    request: request,
                    cancellation: cancellation
                ) { progress in
                    progressContinuation.yield(progress)
                }

                progressContinuation.yield(CollectProgress(
                    phase: result.status == .completed ? .finished : .cancelled,
                    completedUnitCount: result.counts.found,
                    totalUnitCount: result.counts.found,
                    currentItem: nil,
                    counts: result.counts,
                    message: result.status == .completed ? "Collect completed." : "Collect stopped by user."
                ))
                progressContinuation.finish()
                return result
            } catch {
                progressContinuation.finish()
                throw error
            }
        }
    }

    func result() async throws -> CollectResult {
        try await task.value
    }

    func cancel() async {
        await cancellation.cancel()
    }

    private static func validate(request: CollectRequest) throws {
        let manager = FileManager.default

        guard request.xmlURL != nil || request.premiereProjectURL != nil else {
            throw CollectMediaServiceError.missingSourceDocument
        }

        if let xmlURL = request.xmlURL {
            let xmlPath = xmlURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !xmlPath.isEmpty, manager.fileExists(atPath: xmlPath) else {
                throw CollectMediaServiceError.invalidXMLPath
            }
        }

        if let premiereProjectURL = request.premiereProjectURL {
            let projectPath = premiereProjectURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectPath.isEmpty, manager.fileExists(atPath: projectPath) else {
                throw CollectMediaServiceError.invalidPremiereProjectPath
            }
        }

        let destinationPath = request.destinationURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destinationPath.isEmpty else { throw CollectMediaServiceError.missingDestination }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CollectMediaServiceError.invalidDestinationPath
        }

        if let searchRoot = request.options.searchRoot {
            var searchIsDirectory: ObjCBool = false
            guard manager.fileExists(atPath: searchRoot.path, isDirectory: &searchIsDirectory), searchIsDirectory.boolValue else {
                throw CollectMediaServiceError.invalidSearchRootPath
            }
        }
    }

    private static func parseDocuments(
        request: CollectRequest,
        xmlParser: CollectMediaXMLParser,
        premiereProjectParser: CollectMediaPremiereProjectParser
    ) throws -> ParsedCollectMediaDocument {
        var entriesByPath: [String: CollectMediaEntry] = [:]
        var parserRows: [CollectReportRow] = []

        if let xmlURL = request.xmlURL {
            let parsedXML = try xmlParser.parse(xmlURL: xmlURL)
            merge(parsedXML, into: &entriesByPath, parserRows: &parserRows)
        }

        if let premiereProjectURL = request.premiereProjectURL {
            let parsedProject = try premiereProjectParser.parse(projectURL: premiereProjectURL)
            merge(parsedProject, into: &entriesByPath, parserRows: &parserRows)
        }

        return ParsedCollectMediaDocument(
            entries: Array(entriesByPath.values).sorted { $0.sourcePath < $1.sourcePath },
            parserRows: parserRows
        )
    }

    private static func merge(
        _ parsed: ParsedCollectMediaDocument,
        into entriesByPath: inout [String: CollectMediaEntry],
        parserRows: inout [CollectReportRow]
    ) {
        for entry in parsed.entries {
            if let existing = entriesByPath[entry.sourcePath] {
                entriesByPath[entry.sourcePath] = CollectMediaEntry(
                    id: existing.id,
                    sourcePath: existing.sourcePath,
                    basename: existing.basename,
                    fileExtension: existing.fileExtension,
                    expectedTimecodeStart: existing.expectedTimecodeStart ?? entry.expectedTimecodeStart,
                    expectedDurationSeconds: existing.expectedDurationSeconds ?? entry.expectedDurationSeconds,
                    expectedSizeBytes: existing.expectedSizeBytes ?? entry.expectedSizeBytes
                )
            } else {
                entriesByPath[entry.sourcePath] = entry
            }
        }

        parserRows.append(contentsOf: parsed.parserRows)
    }

    private static func sourceDocumentSummary(for request: CollectRequest) -> String {
        [request.xmlURL?.path, request.premiereProjectURL?.path]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
