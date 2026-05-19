import Foundation
import CryptoKit

// MARK: - Target Extensions

let targetExtensions: Set<String> = [
    "mxf", "mov", "mp4", "mts", "m2ts", "r3d", "braw", "ari", "dng", "prores",
    "jpg", "jpeg", "png", "tif", "tiff", "psd", "ai", "eps", "heic", "raw", "cr2", "arw",
    "pdf", "doc", "docx", "xls", "xlsx"
]

let minFileSize: Int64 = 100 * 1024  // 100 KB
let chunkSize = 8 * 1024 * 1024       // 8 MB

// MARK: - Scanner

actor FileScanner {

    // MARK: Scan

    func scanFiles(in rootURL: URL, onProgress: @escaping @MainActor (Double, String) -> Void) async throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        // Collect synchronously to avoid Swift 6 actor isolation issue with enumerator
        let allURLs: [URL] = enumerator.compactMap { $0 as? URL }

        var results: [URL] = []
        for (count, url) in allURLs.enumerated() {
            if count % 50 == 0 {
                let name = url.lastPathComponent
                await onProgress(0, name)
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  Int64(size) >= minFileSize,
                  targetExtensions.contains(url.pathExtension.lowercased())
            else { continue }
            results.append(url)
        }
        return results
    }

    // MARK: Find Duplicates

    func findDuplicates(
        in files: [URL],
        onProgress: @escaping @MainActor (Double, String) -> Void
    ) async throws -> [DuplicateGroup] {

        // Step 1: fast hash (first+last 8MB)
        var fastBuckets: [String: [URL]] = [:]
        for (i, url) in files.enumerated() {
            let progress = Double(i) / Double(files.count) * 0.5
            await onProgress(progress, url.lastPathComponent)

            if let h = fastHash(url) {
                fastBuckets[h, default: []].append(url)
            }
        }

        let candidates = fastBuckets.values.filter { $0.count > 1 }

        // Step 2: full hash for confirmation
        var fullBuckets: [String: [URL]] = [:]
        let candidateFiles = candidates.flatMap { $0 }
        for (i, url) in candidateFiles.enumerated() {
            let progress = 0.5 + Double(i) / Double(max(candidateFiles.count, 1)) * 0.5
            await onProgress(progress, url.lastPathComponent)

            if let h = fullHash(url) {
                fullBuckets[h, default: []].append(url)
            }
        }

        let fm = FileManager.default
        return fullBuckets.values
            .filter { $0.count > 1 }
            .flatMap { exactDuplicateBuckets(from: $0) }
            .filter { $0.count > 1 }
            .map { urls -> DuplicateGroup in
                let scanned = urls.compactMap { url -> ScannedFile? in
                    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                          let size = attrs[.size] as? Int64,
                          let modified = attrs[.modificationDate] as? Date
                    else { return nil }
                    return ScannedFile(url: url, size: size, modifiedDate: modified)
                }.sorted { $0.modifiedDate < $1.modifiedDate }  // oldest first
                return DuplicateGroup(files: scanned)
            }
            .sorted { $0.wastedBytes > $1.wastedBytes }  // biggest waste first
    }

    // MARK: - Hashing

    private func fastHash(_ url: URL) -> String? {
        guard let fh = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? fh.close() }

        var hasher = MD5()
        if let data = try? fh.read(upToCount: chunkSize) {
            hasher.update(data: data)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > chunkSize * 2 {
            if let _ = try? fh.seek(toOffset: UInt64(max(0, size - chunkSize))),
               let tail = try? fh.readToEnd() {
                hasher.update(data: tail)
            }
        }

        let digest = hasher.finalize()
        return "fast:\(size):\(digest.map { String(format: "%02x", $0) }.joined())"
    }

    private func fullHash(_ url: URL) -> String? {
        guard let fh = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? fh.close() }

        var hasher = MD5()
        while let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func exactDuplicateBuckets(from urls: [URL]) -> [[URL]] {
        var buckets: [[URL]] = []

        for url in urls {
            if let index = buckets.firstIndex(where: { bucket in
                guard let representative = bucket.first else { return false }
                return filesAreExactlyEqual(representative, url)
            }) {
                buckets[index].append(url)
            } else {
                buckets.append([url])
            }
        }

        return buckets
    }

    private func filesAreExactlyEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        guard lhs != rhs,
              let lhsHandle = FileHandle(forReadingAtPath: lhs.path),
              let rhsHandle = FileHandle(forReadingAtPath: rhs.path)
        else { return false }
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }

        let lhsSize = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let rhsSize = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
        guard lhsSize == rhsSize else { return false }

        while true {
            guard let lhsChunk = try? lhsHandle.read(upToCount: chunkSize),
                  let rhsChunk = try? rhsHandle.read(upToCount: chunkSize)
            else { return false }

            if lhsChunk != rhsChunk {
                return false
            }

            if lhsChunk.isEmpty {
                return rhsChunk.isEmpty
            }
        }
    }

    // MARK: - Quarantine

    func quarantine(_ files: [ScannedFile], to quarantineURL: URL) throws -> [QuarantineEntry] {
        let fm = FileManager.default
        try fm.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        var entries: [QuarantineEntry] = []

        for file in files {
            var dest = quarantineURL.appendingPathComponent(file.name)
            if fm.fileExists(atPath: dest.path) {
                let stem = file.url.deletingPathExtension().lastPathComponent
                let ext = file.url.pathExtension
                let parent = file.url.deletingLastPathComponent().lastPathComponent
                dest = quarantineURL.appendingPathComponent("\(stem)__\(parent).\(ext)")
            }
            try fm.moveItem(at: file.url, to: dest)
            entries.append(QuarantineEntry(
                originalPath: file.path,
                quarantinePath: dest.path,
                date: Date(),
                groupHash: file.name
            ))
        }
        return entries
    }

    // MARK: - Trash

    func trash(_ files: [ScannedFile]) throws {
        let fm = FileManager.default

        for file in files {
            var trashedItemURL: NSURL?
            try fm.trashItem(at: file.url, resultingItemURL: &trashedItemURL)
        }
    }

    // MARK: - Export CSV

    func exportCSV(groups: [DuplicateGroup], to url: URL) throws {
        var lines = ["group_id,file_path,size_mb,modified,status"]
        for (gid, group) in groups.enumerated() {
            for (i, file) in group.files.enumerated() {
                let sizeMB = String(format: "%.1f", Double(file.size) / 1_048_576)
                let status = group.selectedIndexes.contains(i) ? "DUPLICATE" : "KEEP"
                lines.append("\(gid+1),\"\(file.path)\",\(sizeMB),\(file.modifiedFormatted),\(status)")
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MD5 wrapper using CryptoKit
private struct MD5: HashFunction {
    static let blockByteCount = 64
    static let byteCount = 16
    private var state = Insecure.MD5()
    mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer: bufferPointer) }
    func finalize() -> Insecure.MD5.Digest { state.finalize() }
}
