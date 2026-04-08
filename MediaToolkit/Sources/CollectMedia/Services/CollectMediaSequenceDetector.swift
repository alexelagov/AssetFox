import Foundation

struct SequenceMatch: Sendable {
    var prefix: String
    var digitCount: Int
    var fileExtension: String
}

struct CollectMediaSequenceDetector {
    private let imageSequenceExtensions: Set<String> = [
        "exr", "dpx", "tif", "tiff", "png", "jpg", "jpeg"
    ]

    func detectSequence(for url: URL) -> SequenceMatch? {
        let fileExtension = url.pathExtension.lowercased()
        guard imageSequenceExtensions.contains(fileExtension) else {
            return nil
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let suffixDigits = stem.reversed().prefix { $0.isNumber }.reversed()
        guard !suffixDigits.isEmpty else {
            return nil
        }

        let digits = String(suffixDigits)
        let prefix = String(stem.dropLast(digits.count))
        guard !prefix.isEmpty else {
            return nil
        }

        return SequenceMatch(prefix: prefix, digitCount: digits.count, fileExtension: fileExtension)
    }

    func frames(for sourceURL: URL, sequence: SequenceMatch) -> [URL] {
        let manager = FileManager.default
        let folderURL = sourceURL.deletingLastPathComponent()

        guard let contents = try? manager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [sourceURL]
        }

        let matches = contents.filter { candidate in
            candidate.pathExtension.lowercased() == sequence.fileExtension &&
            matchesSequenceStem(candidate.deletingPathExtension().lastPathComponent, sequence: sequence)
        }

        return matches.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func sequenceFolderName(for sequence: SequenceMatch) -> String {
        let trimmed = sequence.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        let base = trimmed.isEmpty ? "sequence" : trimmed
        return base.replacingOccurrences(of: "/", with: "_") + "_SEQ"
    }

    private func matchesSequenceStem(_ stem: String, sequence: SequenceMatch) -> Bool {
        guard stem.hasPrefix(sequence.prefix) else { return false }
        let suffix = String(stem.dropFirst(sequence.prefix.count))
        return suffix.count == sequence.digitCount && suffix.allSatisfy(\.isNumber)
    }
}
