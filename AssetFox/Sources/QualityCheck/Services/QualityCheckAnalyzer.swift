import Foundation

struct QualityCheckAnalyzer: Sendable {
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
        findings.append(contentsOf: compareCutPoints(fileAnalyses, referenceItemID: referenceItemID, toleranceFrames: toleranceFrames))

        return QualityCheckAnalysisResult(
            findings: findings.sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return severityRank(lhs.severity) > severityRank(rhs.severity)
                }
                return lhs.timeSeconds < rhs.timeSeconds
            },
            rawOutputs: rawOutputs
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

        let outputs = await [black, freeze, scene]
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

        return PerFileAnalysis(item: item, findings: findings, cutPoints: cutPoints, rawOutput: rawOutput)
    }

    private func compareCutPoints(_ analyses: [PerFileAnalysis], referenceItemID: UUID?, toleranceFrames: Int) -> [QualityCheckFinding] {
        guard analyses.count >= 2 else { return [] }
        guard let reference = analyses.first(where: { $0.item.id == referenceItemID }) ?? analyses.first else { return [] }

        var findings: [QualityCheckFinding] = []
        let frameRate = QualityCheckFormatting.normalizedFrameRate(reference.item.nominalFrameRate)
        let toleranceSeconds = QualityCheckFormatting.seconds(forFrame: toleranceFrames, frameRate: frameRate)

        for candidate in analyses where candidate.item.id != reference.item.id {
            for referenceCut in reference.cutPoints where !candidate.cutPoints.contains(where: { abs($0 - referenceCut) <= toleranceSeconds }) {
                findings.append(
                    QualityCheckFinding(
                        severity: .warning,
                        kind: .cutMismatch,
                        fileName: candidate.item.name,
                        timeSeconds: referenceCut,
                        message: "Expected cut point is missing compared with \(reference.item.name)",
                        details: "Tolerance: \(toleranceFrames) frames @ \(String(format: "%.3f", frameRate).replacingOccurrences(of: ".000", with: "")) fps"
                    )
                )
            }

            for candidateCut in candidate.cutPoints where !reference.cutPoints.contains(where: { abs($0 - candidateCut) <= toleranceSeconds }) {
                findings.append(
                    QualityCheckFinding(
                        severity: .warning,
                        kind: .cutMismatch,
                        fileName: candidate.item.name,
                        timeSeconds: candidateCut,
                        message: "Extra cut point compared with \(reference.item.name)",
                        details: "Tolerance: \(toleranceFrames) frames @ \(String(format: "%.3f", frameRate).replacingOccurrences(of: ".000", with: "")) fps"
                    )
                )
            }
        }

        return findings
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

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    processBox.clear(process)
                    return ProcessResult(exitCode: -1, output: "", errorOutput: error.localizedDescription)
                }

                processBox.clear(process)
                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return ProcessResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
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
