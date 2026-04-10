import SwiftUI

@MainActor
@Observable
final class AppViewModel {

    // MARK: State
    var rootURL: URL? = nil
    var phase: ScanPhase = .idle
    var groups: [DuplicateGroup] = []
    var selectedGroupID: UUID? = nil
    var quarantineLog: [QuarantineEntry] = []

    var totalWasted: String {
        let bytes = groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var resolvedGroups: Int { groups.filter { !$0.selectedIndexes.isEmpty }.count }

    // MARK: Scan

    private let scanner = FileScanner()
    private var activeScanSession = UUID()

    func startScan() {
        guard let root = rootURL else { return }
        let sessionID = UUID()
        activeScanSession = sessionID
        phase = .scanning(progress: 0, current: "")
        groups = []
        selectedGroupID = nil

        Task {
            do {
                let files = try await scanner.scanFiles(in: root) { [weak self] _, name in
                    Task { @MainActor in
                        guard self?.activeScanSession == sessionID else { return }
                        self?.phase = .scanning(progress: 0, current: name)
                    }
                }

                guard activeScanSession == sessionID else { return }
                phase = .hashing(progress: 0, current: "")

                let found = try await scanner.findDuplicates(in: files) { [weak self] p, name in
                    Task { @MainActor in
                        guard self?.activeScanSession == sessionID else { return }
                        self?.phase = .hashing(progress: p, current: name)
                    }
                }

                guard activeScanSession == sessionID else { return }
                groups = found
                phase = .done
                if let first = groups.first { selectedGroupID = first.id }

            } catch {
                guard activeScanSession == sessionID else { return }
                phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: Group Actions

    func toggleSelection(groupID: UUID, index: Int) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }

        if groups[i].selectedIndexes.contains(index) {
            groups[i].selectedIndexes.remove(index)
            return
        }

        let keptCount = groups[i].files.count - groups[i].selectedIndexes.count
        guard keptCount > 1 else { return }
        groups[i].selectedIndexes.insert(index)
    }

    func quarantineGroup(_ group: DuplicateGroup) {
        guard let root = rootURL else { return }
        let quarantineURL = root.appendingPathComponent("_DUPLICATES_QUARANTINE")
        let filesToMove = group.selectedFiles

        guard !filesToMove.isEmpty else { return }

        Task {
            do {
                let entries = try await scanner.quarantine(filesToMove, to: quarantineURL)
                quarantineLog.append(contentsOf: entries)
                applyActionResult(groupID: group.id, removedFileIDs: Set(filesToMove.map(\.id)))
            } catch {
                phase = .error("Move failed: \(error.localizedDescription)")
            }
        }
    }

    func quarantineAll() {
        guard let root = rootURL else { return }
        let quarantineURL = root.appendingPathComponent("_DUPLICATES_QUARANTINE")
        let groupsToMove = groups

        Task {
            do {
                for group in groupsToMove {
                    let filesToMove = group.selectedFiles
                    guard !filesToMove.isEmpty else { continue }
                    let entries = try await scanner.quarantine(filesToMove, to: quarantineURL)
                    quarantineLog.append(contentsOf: entries)
                    applyActionResult(groupID: group.id, removedFileIDs: Set(filesToMove.map(\.id)))
                }
            } catch {
                phase = .error("Move failed: \(error.localizedDescription)")
            }
        }
    }

    func trashGroup(_ group: DuplicateGroup) {
        let filesToTrash = group.selectedFiles

        guard !filesToTrash.isEmpty else { return }

        Task {
            do {
                try await scanner.trash(filesToTrash)
                applyActionResult(groupID: group.id, removedFileIDs: Set(filesToTrash.map(\.id)))
            } catch {
                phase = .error("Delete failed: \(error.localizedDescription)")
            }
        }
    }

    func trashAll() {
        let groupsToTrash = groups

        Task {
            do {
                for group in groupsToTrash {
                    let filesToTrash = group.selectedFiles
                    guard !filesToTrash.isEmpty else { continue }
                    try await scanner.trash(filesToTrash)
                    applyActionResult(groupID: group.id, removedFileIDs: Set(filesToTrash.map(\.id)))
                }
            } catch {
                phase = .error("Delete failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Export

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duplicates_report.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                try? await self.scanner.exportCSV(groups: self.groups, to: url)
            }
        }
    }

    func reset() {
        activeScanSession = UUID()
        phase = .idle
        groups = []
        selectedGroupID = nil
        rootURL = nil
    }

    private func removeGroupAndAdvanceSelection(_ groupID: UUID) {
        guard let removedIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }

        groups.removeAll { $0.id == groupID }

        guard selectedGroupID == groupID else { return }
        if removedIndex < groups.count {
            selectedGroupID = groups[removedIndex].id
        } else {
            selectedGroupID = groups.last?.id
        }
    }

    private func applyActionResult(groupID: UUID, removedFileIDs: Set<UUID>) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }

        let remainingFiles = groups[index].files.filter { !removedFileIDs.contains($0.id) }

        if remainingFiles.count <= 1 {
            removeGroupAndAdvanceSelection(groupID)
            return
        }

        groups[index].files = remainingFiles
        groups[index].selectedIndexes = []
    }
}
