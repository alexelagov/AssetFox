import AppKit
import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class QualityCheckViewModel {
    var items: [QualityCheckVideoItem] = []
    var selectedItemID: UUID?
    var referenceItemID: UUID?
    var isPlaying = false
    var isAudioMuted = false
    var currentTime: Double = 0
    var toleranceFrames: Int = 2
    var analysisStatus = "Idle"
    var isAnalyzing = false
    var findings: [QualityCheckFinding] = []
    var rawOutputs: [QualityCheckAnalyzerOutput] = []
    var errorMessage: String?

    @ObservationIgnored private var players: [UUID: AVPlayer] = [:]
    @ObservationIgnored private var timeObservers: [UUID: Any] = [:]
    @ObservationIgnored private var analysisTask: Task<Void, Never>?

    var runtimeSnapshot: FFmpegRuntimeSnapshot {
        FFmpegRuntimeResolver.snapshot()
    }

    var selectedItem: QualityCheckVideoItem? {
        guard let selectedItemID else { return items.first }
        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    var referenceItem: QualityCheckVideoItem? {
        guard let referenceItemID else { return items.first }
        return items.first(where: { $0.id == referenceItemID }) ?? items.first
    }

    var manualReferenceItem: QualityCheckVideoItem? {
        guard let referenceItemID else { return nil }
        return items.first(where: { $0.id == referenceItemID })
    }

    var hasManualReference: Bool {
        manualReferenceItem != nil
    }

    var totalDuration: Double {
        items.map(\.durationSeconds).max() ?? 0
    }

    var timelineFrameRate: Double {
        QualityCheckFormatting.normalizedFrameRate(referenceItem?.nominalFrameRate ?? 0)
    }

    var currentFrame: Int {
        QualityCheckFormatting.frameIndex(for: currentTime, frameRate: timelineFrameRate)
    }

    var totalFrames: Int {
        QualityCheckFormatting.frameIndex(for: totalDuration, frameRate: timelineFrameRate)
    }

    var currentFrameTimecode: String {
        QualityCheckFormatting.formatFrameTimecode(currentTime, frameRate: timelineFrameRate)
    }

    var totalFrameTimecode: String {
        QualityCheckFormatting.formatFrameTimecode(totalDuration, frameRate: timelineFrameRate)
    }

    var referenceFrameRateLabel: String {
        let frameRate = String(format: "%.3f fps", timelineFrameRate).replacingOccurrences(of: ".000", with: "")
        guard let referenceItem else { return frameRate }
        return "\(frameRate) • \(referenceItem.name)"
    }

    var selectedCountLabel: String {
        "\(items.count) Video\(items.count == 1 ? "" : "s")"
    }

    func player(for item: QualityCheckVideoItem) -> AVPlayer {
        if let player = players[item.id] {
            player.isMuted = shouldMutePlayer(id: item.id)
            return player
        }

        let player = AVPlayer(url: item.url)
        player.actionAtItemEnd = .pause
        player.isMuted = shouldMutePlayer(id: item.id)
        players[item.id] = player
        addTimeObserver(for: item.id, player: player)
        return player
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Choose Videos for Quality Check"
        panel.message = "Select two or more exports to compare."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]

        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func add(urls: [URL]) {
        let validURLs = urls.filter { $0.isFileURL }
        guard !validURLs.isEmpty else { return }

        Task {
            var loadedItems: [QualityCheckVideoItem] = []
            for url in validURLs where !items.contains(where: { $0.url == url }) {
                loadedItems.append(await loadItem(url: url))
            }

            guard !loadedItems.isEmpty else { return }
            items.append(contentsOf: loadedItems)
            if selectedItemID == nil {
                selectedItemID = items.first?.id
            }
            updateAudioRouting()
            findings.removeAll()
            rawOutputs.removeAll()
        }
    }

    func remove(_ item: QualityCheckVideoItem) {
        pause()
        if let observer = timeObservers[item.id], let player = players[item.id] {
            player.removeTimeObserver(observer)
        }
        timeObservers[item.id] = nil
        players[item.id] = nil
        items.removeAll { $0.id == item.id }
        findings.removeAll()
        rawOutputs.removeAll()

        if selectedItemID == item.id {
            selectedItemID = items.first?.id
        }
        if referenceItemID == item.id {
            referenceItemID = nil
        }
        updateAudioRouting()
    }

    func clear() {
        cancelAnalysis()
        pause()
        for (id, observer) in timeObservers {
            players[id]?.removeTimeObserver(observer)
        }
        timeObservers.removeAll()
        players.removeAll()
        items.removeAll()
        selectedItemID = nil
        referenceItemID = nil
        currentTime = 0
        findings.removeAll()
        rawOutputs.removeAll()
        analysisStatus = "Idle"
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !items.isEmpty else { return }
        updateAudioRouting()
        seekAll(to: currentTime)
        for item in items {
            player(for: item).play()
        }
        isPlaying = true
    }

    func pause() {
        for player in players.values {
            player.pause()
        }
        isPlaying = false
    }

    func seekAll(to seconds: Double) {
        let frame = QualityCheckFormatting.frameIndex(for: seconds, frameRate: timelineFrameRate)
        seekAll(toFrame: frame)
    }

    func seekAll(toFrame frame: Int) {
        let clampedFrame = min(max(frame, 0), max(totalFrames, 0))
        let snappedSeconds = min(QualityCheckFormatting.seconds(forFrame: clampedFrame, frameRate: timelineFrameRate), totalDuration)
        currentTime = snappedSeconds
        let time = CMTime(seconds: snappedSeconds, preferredTimescale: 600)
        for item in items {
            player(for: item).seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func stepBackward() {
        pause()
        seekAll(toFrame: currentFrame - 1)
    }

    func stepForward() {
        pause()
        seekAll(toFrame: currentFrame + 1)
    }

    func seek(to finding: QualityCheckFinding) {
        pause()
        selectedItemID = items.first(where: { $0.name == finding.fileName })?.id ?? selectedItemID
        seekAll(to: finding.timeSeconds)
    }

    func setReference(_ item: QualityCheckVideoItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        referenceItemID = item.id
        selectedItemID = item.id
        updateAudioRouting()
        findings.removeAll()
        rawOutputs.removeAll()
        analysisStatus = "Idle"
    }

    func toggleAudioMuted() {
        isAudioMuted.toggle()
        updateAudioRouting()
    }

    func frameRate(for finding: QualityCheckFinding) -> Double {
        QualityCheckFormatting.normalizedFrameRate(items.first(where: { $0.name == finding.fileName })?.nominalFrameRate ?? timelineFrameRate)
    }

    func analyze() {
        guard !items.isEmpty else { return }
        cancelAnalysis()

        isAnalyzing = true
        findings.removeAll()
        rawOutputs.removeAll()
        analysisStatus = "Preparing analysis"

        let analyzer = QualityCheckAnalyzer()
        let itemsToAnalyze = items
        let referenceID = referenceItem?.id
        let tolerance = toleranceFrames

        analysisTask = Task { [weak self] in
            do {
                let result = try await analyzer.analyze(items: itemsToAnalyze, referenceItemID: referenceID, toleranceFrames: tolerance) { status in
                    await MainActor.run {
                        self?.analysisStatus = status
                    }
                }

                guard !Task.isCancelled else { return }
                self?.findings = result.findings
                self?.rawOutputs = result.rawOutputs
                self?.analysisStatus = result.findings.isEmpty ? "No findings" : "\(result.findings.count) findings"
                self?.isAnalyzing = false
            } catch is CancellationError {
                self?.analysisStatus = "Cancelled"
                self?.isAnalyzing = false
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.analysisStatus = "Failed"
                self?.isAnalyzing = false
            }
        }
    }

    func exportFindingsTXT() {
        guard !findings.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Export QC Results"
        panel.nameFieldStringValue = defaultFindingsExportName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try findingsReportText().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Could not export QC results: \(error.localizedDescription)"
            }
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        if isAnalyzing {
            analysisStatus = "Cancelled"
        }
        isAnalyzing = false
    }

    private func loadItem(url: URL) async -> QualityCheckVideoItem {
        let asset = AVURLAsset(url: url)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        do {
            async let duration = asset.load(.duration)
            async let tracks = asset.loadTracks(withMediaType: .video)
            let (durationTime, videoTracks) = try await (duration, tracks)
            let videoTrack = videoTracks.first
            let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
            let transform = try await videoTrack?.load(.preferredTransform) ?? .identity
            let transformedSize = naturalSize.applying(transform)
            let nominalFrameRate = Double(try await videoTrack?.load(.nominalFrameRate) ?? 0)
            let durationSeconds = CMTimeGetSeconds(durationTime)

            return QualityCheckVideoItem(
                url: url,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                naturalSize: CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height)),
                nominalFrameRate: nominalFrameRate,
                fileSize: fileSize
            )
        } catch {
            return QualityCheckVideoItem(url: url, fileSize: fileSize)
        }
    }

    private func addTimeObserver(for id: UUID, player: AVPlayer) {
        guard timeObservers[id] == nil else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObservers[id] = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }

            Task { @MainActor [weak self] in
                guard let self, self.selectedItemID == nil || self.selectedItemID == id else { return }
                let frame = QualityCheckFormatting.frameIndex(for: seconds, frameRate: self.timelineFrameRate)
                self.currentTime = QualityCheckFormatting.seconds(forFrame: frame, frameRate: self.timelineFrameRate)
            }
        }
    }

    private func updateAudioRouting() {
        for (id, player) in players {
            player.isMuted = shouldMutePlayer(id: id)
        }
    }

    private func shouldMutePlayer(id: UUID) -> Bool {
        isAudioMuted || id != referenceItem?.id
    }

    private var defaultFindingsExportName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "assetfox-qc-results-\(formatter.string(from: Date())).txt"
    }

    private func findingsReportText() -> String {
        let referenceName = manualReferenceItem?.name ?? "Not selected"
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let lines = findings.map { finding in
            let frameRate = frameRate(for: finding)
            let timecode = QualityCheckFormatting.formatFrameTimecode(finding.timeSeconds, frameRate: frameRate)
            let duration = finding.durationSeconds.map { QualityCheckFormatting.formatFrameDuration($0, frameRate: frameRate) } ?? "-"
            let details = finding.details.map { "\n  Details: \($0)" } ?? ""

            return """
            [\(finding.severity.rawValue)] \(finding.kind.rawValue)
              File: \(finding.fileName)
              Timecode: \(timecode)
              Duration: \(duration)
              Message: \(finding.message)\(details)
            """
        }

        return """
        AssetFox Quality Check Results
        Generated: \(generatedAt)
        Reference: \(referenceName)
        Videos: \(items.count)
        Findings: \(findings.count)

        \(lines.joined(separator: "\n\n"))
        """
    }
}
