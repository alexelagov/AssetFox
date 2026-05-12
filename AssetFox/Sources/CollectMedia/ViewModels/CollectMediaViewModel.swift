import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CollectMediaViewModel {
    var xmlURL: URL?
    var premiereProjectURL: URL?
    var destinationURL: URL?
    var options = CollectOptions()

    var progress = CollectProgress(
        phase: .preparing,
        completedUnitCount: 0,
        totalUnitCount: 0,
        currentItem: nil,
        counts: CollectCounts(),
        message: "Ready."
    )
    var logs: [String] = ["Ready."]
    var summary: CollectResult?
    var errorMessage: String?
    var isCollecting = false
    var ffProbeAvailable = false

    @ObservationIgnored private let service: any CollectMediaRunning
    @ObservationIgnored private var activeRun: (any CollectMediaRun)?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var resultTask: Task<Void, Never>?

    init(service: any CollectMediaRunning = CollectMediaService()) {
        self.service = service
        ffProbeAvailable = FFProbeAdapter().isAvailable
        options.useFFProbe = ffProbeAvailable
    }

    var canCollect: Bool {
        !isCollecting && (xmlURL != nil || premiereProjectURL != nil) && destinationURL != nil
    }

    func selectXML() {
        let panel = NSOpenPanel()
        panel.title = "Select Premiere FCP XML"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.xml]
        if panel.runModal() == .OK {
            xmlURL = panel.url
            appendLog("XML selected: \(panel.url?.path ?? "")")
        }
    }

    func selectPremiereProject() {
        let panel = NSOpenPanel()
        panel.title = "Select Premiere project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "prproj") ?? .data
        ]
        if panel.runModal() == .OK {
            premiereProjectURL = panel.url
            appendLog("Premiere project selected: \(panel.url?.path ?? "")")
        }
    }

    func selectDestination() {
        let panel = NSOpenPanel()
        panel.title = "Select destination folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            destinationURL = panel.url
            appendLog("Destination selected: \(panel.url?.path ?? "")")
        }
    }

    func selectSearchRoot() {
        let panel = NSOpenPanel()
        panel.title = "Select search root folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            options.searchRoot = panel.url
            appendLog("Search root selected: \(panel.url?.path ?? "")")
        }
    }

    func clearSearchRoot() {
        options.searchRoot = nil
        appendLog("Search root cleared.")
    }

    func startCollect() {
        guard xmlURL != nil || premiereProjectURL != nil, let destinationURL else {
            errorMessage = "Please select an XML file or Premiere project, plus a destination folder."
            return
        }

        summary = nil
        errorMessage = nil
        resetProgress()
        isCollecting = true

        let request = CollectRequest(
            xmlURL: xmlURL,
            premiereProjectURL: premiereProjectURL,
            destinationURL: destinationURL,
            options: options
        )

        let run = service.makeRun(request: request)
        activeRun = run
        appendLog("Starting collect in background...")
        Task {
            await TelemetryService.shared.track(.collectMediaStarted)
        }

        progressTask?.cancel()
        progressTask = Task { [weak self] in
            for await update in run.progress {
                await self?.consume(progress: update)
            }
        }

        resultTask?.cancel()
        resultTask = Task { [weak self] in
            do {
                let result = try await run.result()
                await self?.finish(with: result)
            } catch {
                await self?.fail(with: error)
            }
        }
    }

    func stopCollect() {
        guard let activeRun else { return }
        appendLog("Stop requested by user...")
        Task {
            await activeRun.cancel()
        }
    }

    func dismissSummary() {
        summary = nil
    }

    func openDestination(_ result: CollectResult) {
        NSWorkspace.shared.open(result.destinationURL)
    }

    func revealReport(_ result: CollectResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.reportCSVURL])
    }

    func revealMissing(_ result: CollectResult) {
        guard let missingURL = result.missingTextURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([missingURL])
    }

    private func consume(progress update: CollectProgress) {
        progress = update
        if logs.last != update.message {
            appendLog(update.message)
        }
    }

    private func finish(with result: CollectResult) {
        isCollecting = false
        activeRun = nil
        progressTask = nil
        resultTask = nil
        summary = result
        appendLog(result.status == .completed ? "Done." : "Stopped by user.")
        Task {
            await TelemetryService.shared.track(.collectMediaCompleted, properties: [
                "copied_count": .int(result.counts.copied),
                "missing_count": .int(result.counts.missing)
            ])
        }
    }

    private func fail(with error: Error) {
        isCollecting = false
        activeRun = nil
        progressTask = nil
        resultTask = nil
        errorMessage = error.localizedDescription
        appendLog("Error: \(error.localizedDescription)")
    }

    private func resetProgress() {
        progress = CollectProgress(
            phase: .preparing,
            completedUnitCount: 0,
            totalUnitCount: 0,
            currentItem: nil,
            counts: CollectCounts(),
            message: "Starting collect..."
        )
        logs = ["Ready."]
    }

    private func appendLog(_ message: String) {
        logs.append(message)
    }
}
