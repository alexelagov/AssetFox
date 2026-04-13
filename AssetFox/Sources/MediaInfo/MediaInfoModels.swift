import Foundation

enum MediaInfoDeepMetadataSource: String, Sendable {
    case mediaInfoLib = "MediaInfoLib"
}

struct MediaInfoGeneralMetadata: Sendable {
    var completeName: String?
    var containerFormat: String?
    var formatVersion: String?
    var formatProfile: String?
    var formatSettings: String?
    var codecID: String?
    var fileSize: String?
    var duration: String?
    var overallBitRateMode: String?
    var overallBitRate: String?
    var frameRate: String?
    var encodedDate: String?
    var taggedDate: String?
    var writingApplication: String?
    var writingLibrary: String?
}

struct MediaInfoVideoTrackMetadata: Identifiable, Sendable {
    var id: Int { index }

    let index: Int
    var streamID: String?
    var format: String?
    var formatVersion: String?
    var formatProfile: String?
    var codecID: String?
    var codec: String?
    var duration: String?
    var bitRateMode: String?
    var bitRate: String?
    var width: Int?
    var height: Int?
    var widthDisplay: String?
    var heightDisplay: String?
    var displayAspectRatio: String?
    var frameRateMode: String?
    var frameRate: String?
    var colorSpace: String?
    var chromaSubsampling: String?
    var scanType: String?
    var bitsPerPixelFrame: String?
    var streamSize: String?
    var writingLibrary: String?
    var encodedDate: String?
    var taggedDate: String?
    var bitDepth: String?
    var timecode: String?
    var pixelFormat: String?
    var colorPrimaries: String?
    var matrixCoefficients: String?
    var gamma: String?

    var resolutionLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) × \(height)"
    }
}

struct MediaInfoAudioTrackMetadata: Identifiable, Sendable {
    var id: Int { index }

    let index: Int
    var streamID: String?
    var format: String?
    var formatSettings: String?
    var codecID: String?
    var codec: String?
    var duration: String?
    var bitRateMode: String?
    var bitRate: String?
    var channelCount: String?
    var channelLayout: String?
    var sampleRate: String?
    var bitDepth: String?
    var streamSize: String?
    var defaultFlag: String?
    var alternateGroup: String?
    var encodedDate: String?
    var taggedDate: String?
}

struct MediaInfoDeepMetadataResult: Sendable {
    var general: MediaInfoGeneralMetadata
    var videoTracks: [MediaInfoVideoTrackMetadata]
    var audioTracks: [MediaInfoAudioTrackMetadata]
    var source: MediaInfoDeepMetadataSource
    var warnings: [String]
    var errors: [String]
}

enum MediaInfoMetadataMode: String, CaseIterable, Identifiable, Sendable {
    case general
    case video
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .video:
            return "Video"
        case .audio:
            return "Audio"
        }
    }

    var emptyMessage: String {
        switch self {
        case .general:
            return "No general metadata was detected for this file."
        case .video:
            return "No video streams were detected for this file."
        case .audio:
            return "No audio streams were detected for this file."
        }
    }
}

struct MediaInfoInspectorSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    var subtitle: String?
    let rows: [MediaInfoInspectorField]
}

struct MediaInfoInspectorField: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
    var monospace = false
    var isPlaceholder = false
    var alwaysShow = true

    static func required(_ label: String, _ value: String?, monospace: Bool = false) -> Self {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = normalized?.isEmpty == false ? normalized! : "Not detected"
        return Self(label: label, value: detected, monospace: monospace, isPlaceholder: normalized?.isEmpty != false, alwaysShow: true)
    }

    static func optional(_ label: String, _ value: String?, monospace: Bool = false) -> Self {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = normalized?.isEmpty == false ? normalized! : "Not detected"
        return Self(label: label, value: detected, monospace: monospace, isPlaceholder: normalized?.isEmpty != false, alwaysShow: false)
    }
}

struct MediaInfoComparisonEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let sections: [MediaInfoInspectorSection]
}

struct MediaInfoComparisonSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let rows: [MediaInfoComparisonRow]
}

struct MediaInfoComparisonRow: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let values: [MediaInfoComparisonValue]
    let hasDifferences: Bool
}

struct MediaInfoComparisonValue: Identifiable, Sendable {
    let id = UUID()
    let entryID: UUID
    let title: String
    let subtitle: String?
    let value: String
    let monospace: Bool
    let isPlaceholder: Bool
}

struct MediaInfoComparisonService {
    func build(entries: [MediaInfoComparisonEntry], differencesOnly: Bool, showMissingFields: Bool) -> [MediaInfoComparisonSection] {
        guard entries.count >= 2 else { return [] }

        let sectionKeys = orderedSectionKeys(from: entries)

        return sectionKeys.compactMap { key in
            let labels = orderedLabels(for: key, entries: entries)
            let rows = labels.compactMap { label in
                buildRow(
                    for: label,
                    in: key,
                    entries: entries,
                    differencesOnly: differencesOnly,
                    showMissingFields: showMissingFields
                )
            }

            guard !rows.isEmpty else { return nil }
            return MediaInfoComparisonSection(title: key.title, subtitle: key.subtitle, rows: rows)
        }
    }

    private func buildRow(
        for label: String,
        in key: SectionKey,
        entries: [MediaInfoComparisonEntry],
        differencesOnly: Bool,
        showMissingFields: Bool
    ) -> MediaInfoComparisonRow? {
        let values = entries.map { entry -> MediaInfoComparisonValue in
            let row = section(matching: key, in: entry)?.rows.first(where: { $0.label == label })
            return MediaInfoComparisonValue(
                entryID: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                value: row?.value ?? "Not detected",
                monospace: row?.monospace ?? false,
                isPlaceholder: row?.isPlaceholder ?? true
            )
        }

        if !showMissingFields && values.allSatisfy(\.isPlaceholder) {
            return nil
        }

        let hasDifferences = rowHasDifferences(label: label, values: values)

        if differencesOnly && !hasDifferences {
            return nil
        }

        return MediaInfoComparisonRow(label: label, values: values, hasDifferences: hasDifferences)
    }

    private func rowHasDifferences(label: String, values: [MediaInfoComparisonValue]) -> Bool {
        let normalizedValues = values.map { value -> String? in
            guard !value.isPlaceholder else { return nil }
            return canonicalComparisonValue(for: label, value: value.value)
        }

        let uniqueDetected = Set(normalizedValues.compactMap { $0 })
        let placeholderCount = normalizedValues.filter { $0 == nil }.count

        if uniqueDetected.count > 1 {
            return true
        }

        if placeholderCount > 0 && uniqueDetected.count > 0 {
            return true
        }

        return false
    }

    private func canonicalComparisonValue(for label: String, value: String) -> String {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedText = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedLabel.contains("duration"),
           let milliseconds = parseDurationMilliseconds(from: normalizedText) {
            return "duration:\(milliseconds)"
        }

        if (normalizedLabel.contains("bit rate") || normalizedLabel == "overall bit rate"),
           let bitsPerSecond = parseBitRate(from: normalizedText) {
            return "bitrate:\(bitsPerSecond)"
        }

        if normalizedLabel == "frame rate",
           let framesPerSecond = parseFloatingPointValue(from: normalizedText) {
            return String(format: "fps:%.6f", framesPerSecond)
        }

        if normalizedLabel == "file size" || normalizedLabel.contains("stream size"),
           let bytes = parseByteCount(from: normalizedText) {
            return "bytes:\(bytes)"
        }

        if normalizedLabel == "width" || normalizedLabel == "height" || normalizedLabel == "channel(s)",
           let integerValue = parseLeadingInteger(from: normalizedText) {
            return "int:\(integerValue)"
        }

        if normalizedLabel == "sampling rate",
           let sampleRate = parseSampleRate(from: normalizedText) {
            return "hz:\(sampleRate)"
        }

        if normalizedLabel == "display aspect ratio",
           let ratioValue = parseAspectRatio(from: normalizedText) {
            return String(format: "ratio:%.6f", ratioValue)
        }

        return normalizedText
    }

    private func parseDurationMilliseconds(from value: String) -> Int64? {
        let baseValue = value.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value

        if baseValue.contains(":") {
            let timeAndFraction = baseValue.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let timeParts = timeAndFraction[0].split(separator: ":").compactMap { Double($0) }

            guard timeParts.count == 2 || timeParts.count == 3 else { return nil }

            let hours: Double
            let minutes: Double
            let seconds: Double

            if timeParts.count == 3 {
                hours = timeParts[0]
                minutes = timeParts[1]
                seconds = timeParts[2]
            } else {
                hours = 0
                minutes = timeParts[0]
                seconds = timeParts[1]
            }

            let fractionPart = timeAndFraction.count > 1 ? String(timeAndFraction[1]) : ""
            let fractionalMilliseconds = fractionPart.isEmpty ? 0.0 : (Double("0.\(fractionPart)") ?? 0) * 1000
            let totalMilliseconds = (((hours * 60 + minutes) * 60) + seconds) * 1000 + fractionalMilliseconds
            return Int64(totalMilliseconds.rounded())
        }

        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(ms|h|mn|min|s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(baseValue.startIndex..<baseValue.endIndex, in: baseValue)
        let matches = regex.matches(in: baseValue, options: [], range: nsRange)
        guard !matches.isEmpty else { return nil }

        var totalMilliseconds: Double = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let numericRange = Range(match.range(at: 1), in: baseValue),
                  let unitRange = Range(match.range(at: 2), in: baseValue),
                  let numericValue = Double(String(baseValue[numericRange])) else {
                continue
            }

            switch baseValue[unitRange].lowercased() {
            case "h":
                totalMilliseconds += numericValue * 3_600_000
            case "mn", "min":
                totalMilliseconds += numericValue * 60_000
            case "s":
                totalMilliseconds += numericValue * 1_000
            case "ms":
                totalMilliseconds += numericValue
            default:
                break
            }
        }

        return totalMilliseconds > 0 ? Int64(totalMilliseconds.rounded()) : nil
    }

    private func parseBitRate(from value: String) -> Int64? {
        guard let (numericValue, unit) = parseNumberAndUnit(from: value, units: ["gb/s", "mb/s", "kb/s", "b/s"]) else {
            return nil
        }

        let multiplier: Double
        switch unit {
        case "gb/s":
            multiplier = 1_000_000_000
        case "mb/s":
            multiplier = 1_000_000
        case "kb/s":
            multiplier = 1_000
        default:
            multiplier = 1
        }

        return Int64((numericValue * multiplier).rounded())
    }

    private func parseSampleRate(from value: String) -> Int64? {
        guard let (numericValue, unit) = parseNumberAndUnit(from: value, units: ["khz", "hz"]) else {
            return nil
        }

        let multiplier: Double = unit == "khz" ? 1_000 : 1
        return Int64((numericValue * multiplier).rounded())
    }

    private func parseByteCount(from value: String) -> Int64? {
        guard let (numericValue, unit) = parseNumberAndUnit(from: value, units: ["tib", "tb", "gib", "gb", "mib", "mb", "kib", "kb", "b"]) else {
            return nil
        }

        let multiplier: Double
        switch unit {
        case "tib":
            multiplier = pow(1024, 4)
        case "tb":
            multiplier = pow(1000, 4)
        case "gib":
            multiplier = pow(1024, 3)
        case "gb":
            multiplier = pow(1000, 3)
        case "mib":
            multiplier = pow(1024, 2)
        case "mb":
            multiplier = pow(1000, 2)
        case "kib":
            multiplier = 1024
        case "kb":
            multiplier = 1000
        default:
            multiplier = 1
        }

        return Int64((numericValue * multiplier).rounded())
    }

    private func parseAspectRatio(from value: String) -> Double? {
        let baseValue = value.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value

        if baseValue.contains(":") {
            let parts = baseValue.split(separator: ":")
            guard parts.count == 2,
                  let left = Double(parts[0]),
                  let right = Double(parts[1]),
                  right != 0 else {
                return nil
            }
            return left / right
        }

        return Double(baseValue)
    }

    private func parseLeadingInteger(from value: String) -> Int64? {
        let pattern = #"([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return Int64(String(value[range]))
    }

    private func parseFloatingPointValue(from value: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return Double(String(value[range]))
    }

    private func parseNumberAndUnit(from value: String, units: [String]) -> (Double, String)? {
        let escapedUnits = units.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*("# + escapedUnits + #")"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let numericValue = Double(String(value[numberRange])) else {
            return nil
        }

        return (numericValue, String(value[unitRange]).lowercased())
    }

    private func orderedSectionKeys(from entries: [MediaInfoComparisonEntry]) -> [SectionKey] {
        var keys: [SectionKey] = []

        for entry in entries {
            for section in entry.sections {
                let key = SectionKey(title: section.title, subtitle: section.subtitle)
                if !keys.contains(key) {
                    keys.append(key)
                }
            }
        }

        return keys
    }

    private func orderedLabels(for key: SectionKey, entries: [MediaInfoComparisonEntry]) -> [String] {
        var labels: [String] = []

        for entry in entries {
            guard let section = section(matching: key, in: entry) else { continue }
            for row in section.rows where !labels.contains(row.label) {
                labels.append(row.label)
            }
        }

        return labels
    }

    private func section(matching key: SectionKey, in entry: MediaInfoComparisonEntry) -> MediaInfoInspectorSection? {
        entry.sections.first { $0.title == key.title && $0.subtitle == key.subtitle }
    }

    private struct SectionKey: Equatable {
        let title: String
        let subtitle: String?
    }
}
