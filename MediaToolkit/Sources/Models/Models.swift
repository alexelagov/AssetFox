import Foundation

// MARK: - Scanned File

struct ScannedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modifiedDate: Date
    var isKept: Bool = false

    var name: String { url.lastPathComponent }
    var path: String { url.path }
    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var modifiedFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: modifiedDate)
    }
}

// MARK: - Duplicate Group

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var files: [ScannedFile]
    var keepIndex: Int = 0  // index of the file to keep

    var wastedBytes: Int64 {
        Int64(files.count - 1) * (files.first?.size ?? 0)
    }
    var wastedFormatted: String {
        ByteCountFormatter.string(fromByteCount: wastedBytes, countStyle: .file)
    }
    var size: Int64 { files.first?.size ?? 0 }
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Scan State

enum ScanPhase: Equatable {
    case idle
    case scanning(progress: Double, current: String)
    case hashing(progress: Double, current: String)
    case done
    case error(String)
}

// MARK: - Quarantine Log Entry

struct QuarantineEntry: Codable {
    let originalPath: String
    let quarantinePath: String
    let date: Date
    let groupHash: String
}
