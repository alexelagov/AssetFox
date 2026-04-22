import Foundation

enum CollectPreserveMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case baseRoot = "base_root"
    case tailN = "tail_n"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baseRoot:
            return "Relative to base root"
        case .tailN:
            return "Last N folders"
        }
    }
}

struct CollectMediaEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var sourcePath: String
    var basename: String
    var fileExtension: String
    var expectedTimecodeStart: String?
    var expectedDurationSeconds: Double?
    var expectedSizeBytes: Int64?

    init(
        id: UUID = UUID(),
        sourcePath: String,
        basename: String,
        fileExtension: String,
        expectedTimecodeStart: String? = nil,
        expectedDurationSeconds: Double? = nil,
        expectedSizeBytes: Int64? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.basename = basename
        self.fileExtension = fileExtension
        self.expectedTimecodeStart = expectedTimecodeStart
        self.expectedDurationSeconds = expectedDurationSeconds
        self.expectedSizeBytes = expectedSizeBytes
    }
}

struct CollectOptions: Hashable, Codable, Sendable {
    var preserveStructure = false
    var preserveMode: CollectPreserveMode = .baseRoot
    var tailN = 4
    var skipDuplicates = true
    var smartRelink = true
    var useFFProbe = true
    var searchRoot: URL?
    var relinkThreshold = 170
    var durationTolerance = 0.25
}

struct CollectCounts: Equatable, Codable, Sendable {
    var found = 0
    var copied = 0
    var missing = 0
    var skipped = 0
}

struct CollectProgress: Equatable, Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case preparing
        case parsingXML = "parsing_xml"
        case relinking
        case copying
        case writingReports = "writing_reports"
        case finished
        case cancelled
    }

    var phase: Phase
    var completedUnitCount: Int
    var totalUnitCount: Int
    var currentItem: String?
    var counts: CollectCounts
    var message: String
}

enum CollectResultStatus: String, Codable, Sendable {
    case completed
    case stopped
}

struct CollectResult: Equatable, Codable, Sendable {
    var counts: CollectCounts
    var destinationURL: URL
    var reportCSVURL: URL
    var missingTextURL: URL?
    var status: CollectResultStatus
}

struct CollectRequest: Hashable, Codable, Sendable {
    var xmlURL: URL?
    var premiereProjectURL: URL?
    var destinationURL: URL
    var options: CollectOptions
}

actor CollectCancellationController {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

protocol CollectMediaRun: Sendable {
    var progress: AsyncStream<CollectProgress> { get }
    func result() async throws -> CollectResult
    func cancel() async
}

protocol CollectMediaRunning: Sendable {
    func makeRun(request: CollectRequest) -> any CollectMediaRun
}
