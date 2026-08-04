import Foundation

struct QualityCheckAnalyzer: Sendable {
    /// scdet's 0-100 scale. Low on purpose - see QualityCheckCutPoint: the
    /// point is to record weak changes so a consumer can tell "this cut is
    /// absent here" from "this cut scored lower in this crop".
    static let cutDetectionFloor = 4

    private let ffmpegURL: URL?

    init(ffmpegURL: URL? = FFmpegRuntimeResolver.resolve(.ffmpeg).executableURL) {
        self.ffmpegURL = ffmpegURL
    }

    func analyze(
        items: [QualityCheckVideoItem],
        referenceItemID: UUID?,
        toleranceFrames: Int,
        progress: @Sendable @escaping (String) async -> Void
    ) async throws -> QualityCheckAnalysisResult {
        guard let ffmpegURL else {
            return QualityCheckAnalysisResult(
                findings: [
                    QualityCheckFinding(
                        severity: .critical,
                        kind: .runtime,
                        fileName: "Runtime",
                        timeSeconds: 0,
                        message: "ffmpeg is not available. Add bundled tools or install an LGPL-compatible ffmpeg in Homebrew or /usr/local.",
                        details: "Expected bundled path: Contents/Resources/Tools/ffmpeg"
                    )
                ],
                rawOutputs: []
            )
        }

        var fileAnalyses: [PerFileAnalysis] = []
        var findings: [QualityCheckFinding] = []
        var rawOutputs: [QualityCheckAnalyzerOutput] = []

        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            await progress("Analyzing \(item.name) (\(index + 1) of \(items.count))")

            let analysis = await analyze(item: item, ffmpegURL: ffmpegURL)
            fileAnalyses.append(analysis)
            findings.append(contentsOf: analysis.findings)
            rawOutputs.append(QualityCheckAnalyzerOutput(fileName: item.name, rawOutput: analysis.rawOutput))
        }

        await progress("Comparing cut points")
        if referenceItemID != nil {
            findings.append(contentsOf: compareCutPoints(fileAnalyses, referenceItemID: referenceItemID, toleranceFrames: toleranceFrames))
        }

        return QualityCheckAnalysisResult(
            findings: findings.sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return severityRank(lhs.severity) > severityRank(rhs.severity)
                }
                return lhs.timeSeconds < rhs.timeSeconds
            },
            rawOutputs: rawOutputs,
            measurements: fileAnalyses.map(\.measurement)
        )
    }

    private func analyze(item: QualityCheckVideoItem, ffmpegURL: URL) async -> PerFileAnalysis {
        async let black = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostats", "-i", item.url.path, "-vf", "blackdetect=d=0.12:pix_th=0.10:pic_th=0.98", "-an", "-f", "null", "-"]
        )
        async let freeze = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostats", "-i", item.url.path, "-vf", "freezedetect=n=-60dB:d=0.5", "-an", "-f", "null", "-"]
        )
        async let scene = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostats", "-i", item.url.path, "-vf", "select=gt(scene\\,0.35),showinfo", "-an", "-f", "null", "-"]
        )
        // Measurement passes. `-progress pipe:1` puts the decoded frame count
        // and the played duration on stdout as key=value lines, while
        // cropdetect's per-frame report goes to stderr — one decode, both
        // halves of the "declared vs actual" comparison.
        async let bounds = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner", "-nostats", "-progress", "pipe:1", "-i", item.url.path,
                "-map", "0:v:0", "-vf", "cropdetect=limit=24:round=2:reset=0", "-an", "-f", "null", "-"
            ]
        )
        async let decimated = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner", "-nostats", "-progress", "pipe:1", "-i", item.url.path,
                "-map", "0:v:0", "-vf", "mpdecimate", "-an", "-f", "null", "-"
            ]
        )
        // Scene changes with their scores. The threshold is deliberately low:
        // the consumer compares one export against another and needs to see a
        // weak-but-present change, not a yes/no verdict from this pass. The
        // select stage keeps the output to the events themselves.
        async let cuts = runFFmpeg(
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner", "-nostats", "-i", item.url.path, "-map", "0:v:0",
                "-vf",
                "scdet=threshold=\(Self.cutDetectionFloor),"
                    + "metadata=mode=select:key=lavfi.scd.time,"
                    + "metadata=mode=print:file=-",
                "-an", "-f", "null", "-"
            ]
        )

        let outputs = await [black, freeze, scene]
        let boundsResult = await bounds
        let decimatedResult = await decimated
        let cutsResult = await cuts
        let rawOutput = outputs.map(\.combinedOutput).joined(separator: "\n\n")
        let blackSegments = parseBlackSegments(rawOutput)
        let freezeSegments = parseFreezeSegments(rawOutput)
        let cutPoints = parseSceneCutPoints(rawOutput)

        var findings: [QualityCheckFinding] = []
        findings.append(contentsOf: blackSegments.map { segment in
            QualityCheckFinding(
                severity: segment.duration >= 0.5 ? .warning : .info,
                kind: .blackFrame,
                fileName: item.name,
                timeSeconds: segment.start,
                durationSeconds: segment.duration,
                message: "Black segment detected",
                details: "blackdetect: start \(segment.start), duration \(segment.duration)"
            )
        })
        findings.append(contentsOf: freezeSegments.map { segment in
            QualityCheckFinding(
                severity: segment.duration >= 1.0 ? .warning : .info,
                kind: .freezeFrame,
                fileName: item.name,
                timeSeconds: segment.start,
                durationSeconds: segment.duration,
                message: "Freeze segment detected",
                details: "freezedetect: start \(segment.start), duration \(segment.duration)"
            )
        })

        let measurement = measure(
            item: item,
            boundsOutput: boundsResult,
            decimatedOutput: decimatedResult,
            cutsOutput: cutsResult
        )

        return PerFileAnalysis(
            item: item,
            findings: findings,
            cutPoints: cutPoints,
            rawOutput: rawOutput,
            measurement: measurement
        )
    }

    private func measure(
        item: QualityCheckVideoItem,
        boundsOutput: ProcessResult,
        decimatedOutput: ProcessResult,
        cutsOutput: ProcessResult
    ) -> QualityCheckMeasurement {
        var measurement = QualityCheckMeasurement(fileName: item.name)
        measurement.cutPoints = parseCutPoints(cutsOutput.output)

        // cropdetect refines its guess as it goes; the last report is the one
        // that saw the whole file.
        if let crop = lines(in: boundsOutput.errorOutput).last(where: { $0.contains("crop=") }) {
            measurement.contentWidth = intValue(after: "w:", in: crop)
            measurement.contentHeight = intValue(after: "h:", in: crop)
            measurement.contentX = intValue(after: "x:", in: crop)
            measurement.contentY = intValue(after: "y:", in: crop)
        }

        measurement.measuredFrames = progressValue("frame", in: boundsOutput.output).map(Int.init)
        if let micros = progressValue("out_time_us", in: boundsOutput.output), micros > 0 {
            measurement.measuredDurationSeconds = micros / 1_000_000
        }
        measurement.uniqueFrames = progressValue("frame", in: decimatedOutput.output).map(Int.init)

        return measurement
    }

    /// The metadata printer emits a block per selected frame: the scd.time it
    /// was selected on, and the scd.score that produced it.
    private func parseCutPoints(_ text: String) -> [QualityCheckCutPoint] {
        var points: [QualityCheckCutPoint] = []
        var pendingScore: Double?

        for line in lines(in: text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lavfi.scd.score=") {
                pendingScore = value(after: "=", in: trimmed)
            } else if trimmed.hasPrefix("lavfi.scd.time=") {
                guard let time = value(after: "=", in: trimmed) else { continue }
                points.append(QualityCheckCutPoint(timeSeconds: time, score: pendingScore ?? 0))
                pendingScore = nil
            }
        }

        return points
    }

    /// `-progress` repeats its block as the job runs; the final one is the total.
    private func progressValue(_ key: String, in text: String) -> Double? {
        lines(in: text)
            .compactMap { line -> Double? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
                return Double(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .last
    }

    private func intValue(after marker: String, in line: String) -> Int? {
        guard let raw = value(after: marker, in: line), raw.isFinite else { return nil }
        return Int(raw)
    }

    private func compareCutPoints(_ analyses: [PerFileAnalysis], referenceItemID: UUID?, toleranceFrames: Int) -> [QualityCheckFinding] {
        guard analyses.count >= 2 else { return [] }
        guard let referenceItemID,
              let reference = analyses.first(where: { $0.item.id == referenceItemID }) else { return [] }

        var findings: [QualityCheckFinding] = []
        let frameRate = QualityCheckFormatting.normalizedFrameRate(reference.item.nominalFrameRate)
        let matchingToleranceFrames = max(toleranceFrames, 5)
        let clusters = cutPointClusters(
            analyses,
            frameRate: frameRate,
            toleranceFrames: matchingToleranceFrames
        )
        let minimumParticipantCount = max(2, Int((Double(analyses.count) * 0.6).rounded(.up)))

        for cluster in clusters where cluster.participantIDs.count >= minimumParticipantCount && cluster.hasStableTiming(frameTolerance: matchingToleranceFrames) {
            let participantIDs = cluster.participantIDs
            guard participantIDs.contains(reference.item.id) else { continue }

            let clusterTime = cluster.referenceTime(for: reference.item.id) ?? cluster.averageTime
            let details = cutMismatchDetails(
                toleranceFrames: toleranceFrames,
                matchingToleranceFrames: matchingToleranceFrames,
                frameRate: frameRate,
                participantCount: participantIDs.count,
                totalCount: analyses.count
            )

            for candidate in analyses where candidate.item.id != reference.item.id && !participantIDs.contains(candidate.item.id) {
                findings.append(
                    QualityCheckFinding(
                        severity: .warning,
                        kind: .cutMismatch,
                        fileName: candidate.item.name,
                        timeSeconds: clusterTime,
                        message: "Reference cut point is missing in this export",
                        details: details
                    )
                )
            }
        }

        return findings
    }

    private func cutPointClusters(
        _ analyses: [PerFileAnalysis],
        frameRate: Double,
        toleranceFrames: Int
    ) -> [CutPointCluster] {
        let observations = analyses.flatMap { analysis in
            analysis.cutPoints.map { cutPoint in
                CutPointObservation(
                    itemID: analysis.item.id,
                    timeSeconds: cutPoint,
                    frame: QualityCheckFormatting.frameIndex(for: cutPoint, frameRate: frameRate)
                )
            }
        }
        .sorted { $0.frame < $1.frame }

        var clusters: [CutPointCluster] = []
        for observation in observations {
            if let index = clusters.indices.last,
               observation.frame - clusters[index].lastFrame <= toleranceFrames {
                clusters[index].append(observation)
            } else {
                clusters.append(CutPointCluster(observations: [observation]))
            }
        }

        return clusters
    }

    private func cutMismatchDetails(
        toleranceFrames: Int,
        matchingToleranceFrames: Int,
        frameRate: Double,
        participantCount: Int,
        totalCount: Int
    ) -> String {
        let frameRateLabel = String(format: "%.3f", frameRate).replacingOccurrences(of: ".000", with: "")
        if matchingToleranceFrames > toleranceFrames {
            return "Tolerance: \(toleranceFrames) frames @ \(frameRateLabel) fps; detector guard: \(matchingToleranceFrames) frames; reference-confirmed and detected in \(participantCount)/\(totalCount) exports"
        }
        return "Tolerance: \(toleranceFrames) frames @ \(frameRateLabel) fps; reference-confirmed and detected in \(participantCount)/\(totalCount) exports"
    }

    private func runFFmpeg(executableURL: URL, arguments: [String]) async -> ProcessResult {
        let processBox = ProcessBox()

        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                if Task.isCancelled {
                    return ProcessResult(exitCode: -999, output: "", errorOutput: "Cancelled")
                }

                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                processBox.store(process)

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                // Both pipes must be drained WHILE ffmpeg runs. A per-frame
                // filter like cropdetect writes a line per frame, so waiting
                // for exit first fills the 64K pipe buffer and deadlocks:
                // ffmpeg blocks on write, we block on wait.
                let outSink = ByteSink(stdout.fileHandleForReading)
                let errSink = ByteSink(stderr.fileHandleForReading)

                do {
                    try process.run()
                    process.waitUntilExit()
                    outSink.finish()
                    errSink.finish()
                } catch {
                    processBox.clear(process)
                    outSink.finish()
                    errSink.finish()
                    return ProcessResult(exitCode: -1, output: "", errorOutput: error.localizedDescription)
                }

                processBox.clear(process)
                return ProcessResult(
                    exitCode: process.terminationStatus,
                    output: outSink.text,
                    errorOutput: errSink.text
                )
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    private func parseBlackSegments(_ text: String) -> [TimedSegment] {
        lines(in: text).compactMap { line in
            guard line.contains("black_start:") else { return nil }
            let start = value(after: "black_start:", in: line)
            let end = value(after: "black_end:", in: line)
            let duration = value(after: "black_duration:", in: line)
            guard let start else { return nil }
            return TimedSegment(start: start, duration: duration ?? max(0, (end ?? start) - start))
        }
    }

    private func parseFreezeSegments(_ text: String) -> [TimedSegment] {
        var activeStart: Double?
        var segments: [TimedSegment] = []

        for line in lines(in: text) {
            if line.contains("lavfi.freezedetect.freeze_start") {
                activeStart = value(after: "freeze_start:", in: line)
            } else if line.contains("lavfi.freezedetect.freeze_end") {
                let end = value(after: "freeze_end:", in: line)
                let duration = value(after: "freeze_duration:", in: line)
                if let start = activeStart, let end {
                    segments.append(TimedSegment(start: start, duration: duration ?? max(0, end - start)))
                }
                activeStart = nil
            }
        }

        return segments
    }

    private func parseSceneCutPoints(_ text: String) -> [Double] {
        let points = lines(in: text)
            .filter { $0.contains("Parsed_showinfo") && $0.contains("pts_time:") }
            .compactMap { value(after: "pts_time:", in: $0) }

        return Array(Set(points.map { ($0 * 1000).rounded() / 1000 })).sorted()
    }

    private func lines(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func value(after token: String, in line: String) -> Double? {
        guard let tokenRange = line.range(of: token) else { return nil }
        let suffix = line[tokenRange.upperBound...]
        let number = suffix.prefix { character in
            character.isNumber || character == "." || character == "-"
        }
        return Double(number)
    }

    private func severityRank(_ severity: QualityCheckSeverity) -> Int {
        switch severity {
        case .critical: 3
        case .warning: 2
        case .info: 1
        }
    }
}

private struct PerFileAnalysis: Sendable {
    let item: QualityCheckVideoItem
    let findings: [QualityCheckFinding]
    let cutPoints: [Double]
    let rawOutput: String
    let measurement: QualityCheckMeasurement
}

private struct CutPointObservation: Sendable {
    let itemID: UUID
    let timeSeconds: Double
    let frame: Int
}

private struct CutPointCluster: Sendable {
    private(set) var observations: [CutPointObservation]

    var participantIDs: Set<UUID> {
        Set(observations.map(\.itemID))
    }

    var lastFrame: Int {
        observations.last?.frame ?? 0
    }

    var averageTime: Double {
        guard !observations.isEmpty else { return 0 }
        return observations.map(\.timeSeconds).reduce(0, +) / Double(observations.count)
    }

    mutating func append(_ observation: CutPointObservation) {
        if let existingIndex = observations.firstIndex(where: { $0.itemID == observation.itemID }) {
            let existing = observations[existingIndex]
            if abs(observation.frame - centerFrame) < abs(existing.frame - centerFrame) {
                observations[existingIndex] = observation
            }
        } else {
            observations.append(observation)
            observations.sort { $0.frame < $1.frame }
        }
    }

    func referenceTime(for itemID: UUID) -> Double? {
        observations.first(where: { $0.itemID == itemID })?.timeSeconds
    }

    func hasStableTiming(frameTolerance: Int) -> Bool {
        guard let first = observations.first?.frame,
              let last = observations.last?.frame else { return false }
        return last - first <= frameTolerance
    }

    private var centerFrame: Int {
        guard !observations.isEmpty else { return 0 }
        let total = observations.map(\.frame).reduce(0, +)
        return Int((Double(total) / Double(observations.count)).rounded())
    }
}

private struct TimedSegment: Sendable {
    let start: Double
    let duration: Double
}

private struct ProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String

    var combinedOutput: String {
        [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Drains one pipe on its own thread so a chatty ffmpeg filter can never
/// block on a full buffer. `finish()` joins the reader after the process
/// exits, at which point the handle is at EOF and `text` is complete.
private final class ByteSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let reachedEOF = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }
            reachedEOF.signal()
        }
    }

    /// Blocks until the reader sees EOF. Call after the process exits, so
    /// `text` covers everything the child wrote.
    func finish() {
        reachedEOF.wait()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func store(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
