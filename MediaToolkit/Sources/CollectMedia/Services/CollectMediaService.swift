import Foundation

struct CollectMediaService: CollectMediaRunning {
    func makeRun(request: CollectRequest) -> any CollectMediaRun {
        let parser = CollectMediaXMLParser()
        let ffProbeAdapter = FFProbeAdapter()
        let relinker = CollectMediaRelinker(ffProbeAdapter: ffProbeAdapter)
        let collector = CollectMediaCollector(relinker: relinker)
        return ServiceRun(
            request: request,
            parser: parser,
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
        parser: CollectMediaXMLParser,
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
                    currentItem: request.xmlURL.path,
                    counts: CollectCounts(),
                    message: "Parsing XML..."
                ))

                let parsed = try parser.parse(xmlURL: request.xmlURL)
                progressContinuation.yield(CollectProgress(
                    phase: .parsingXML,
                    completedUnitCount: 0,
                    totalUnitCount: parsed.entries.count,
                    currentItem: request.xmlURL.path,
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

        let xmlPath = request.xmlURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !xmlPath.isEmpty else { throw CollectMediaServiceError.missingXML }
        guard manager.fileExists(atPath: xmlPath) else { throw CollectMediaServiceError.invalidXMLPath }

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
}
