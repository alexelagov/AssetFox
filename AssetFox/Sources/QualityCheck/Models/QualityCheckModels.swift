import AVFoundation
import Foundation

struct QualityCheckVideoItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    var durationSeconds: Double
    var naturalSize: CGSize
    var nominalFrameRate: Double
    var fileSize: Int64

    init(
        id: UUID = UUID(),
        url: URL,
        durationSeconds: Double = 0,
        naturalSize: CGSize = .zero,
        nominalFrameRate: Double = 0,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.url = url
        self.durationSeconds = durationSeconds
        self.naturalSize = naturalSize
        self.nominalFrameRate = nominalFrameRate
        self.fileSize = fileSize
    }

    var name: String {
        url.lastPathComponent
    }

    var compactPath: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var formattedDuration: String {
        QualityCheckFormatting.formatTime(durationSeconds)
    }

    var formattedFrameRate: String {
        nominalFrameRate > 0 ? String(format: "%.3f fps", nominalFrameRate).replacingOccurrences(of: ".000", with: "") : "Unknown fps"
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var resolutionLabel: String {
        let width = Int(abs(naturalSize.width))
        let height = Int(abs(naturalSize.height))
        return width > 0 && height > 0 ? "\(width) × \(height)" : "Unknown"
    }

    var aspectRatioValue: Double {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return 16.0 / 9.0 }
        return Double(abs(naturalSize.width / naturalSize.height))
    }

    var aspectRatioLabel: String {
        let ratio = aspectRatioValue
        let known: [(String, Double)] = [
            ("16:9", 16.0 / 9.0),
            ("9:16", 9.0 / 16.0),
            ("4:5", 4.0 / 5.0),
            ("1:1", 1.0)
        ]

        if let match = known.min(by: { abs($0.1 - ratio) < abs($1.1 - ratio) }), abs(match.1 - ratio) < 0.04 {
            return match.0
        }
        return String(format: "%.2f:1", ratio)
    }
}

enum QualityCheckSeverity: String, CaseIterable, Identifiable, Sendable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"

    var id: String { rawValue }
}

enum QualityCheckFindingKind: String, Sendable {
    case blackFrame = "Black"
    case freezeFrame = "Freeze"
    case cutMismatch = "Cut Mismatch"
    case runtime = "Runtime"
}

struct QualityCheckFinding: Identifiable, Sendable {
    let id: UUID
    var severity: QualityCheckSeverity
    var kind: QualityCheckFindingKind
    var fileName: String
    var timeSeconds: Double
    var durationSeconds: Double?
    var message: String
    var details: String?

    init(
        id: UUID = UUID(),
        severity: QualityCheckSeverity,
        kind: QualityCheckFindingKind,
        fileName: String,
        timeSeconds: Double,
        durationSeconds: Double? = nil,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.kind = kind
        self.fileName = fileName
        self.timeSeconds = timeSeconds
        self.durationSeconds = durationSeconds
        self.message = message
        self.details = details
    }
}

struct QualityCheckAnalyzerOutput: Identifiable, Sendable {
    let id = UUID()
    var fileName: String
    var rawOutput: String
}

/// Per-file numbers a QC pass measures rather than judges. Findings say
/// "something happened at 12.4s"; these say "this is what the file is",
/// and the caller compares them against whatever the delivery spec asked
/// for. Every field is optional: ffmpeg may fail on one pass and not the
/// other, and a missing number must stay missing rather than become 0.
/// One detected scene change, with the score that detected it. The score is
/// what makes cross-export comparison possible: the same cut scores
/// differently in a 16:9 and a 9:16 crop of one edit, because the crop
/// changes how much of the frame the cut moves, so "was it detected" is a
/// worse question than "how strong was the change here".
struct QualityCheckCutPoint: Sendable {
    var timeSeconds: Double
    var score: Double
}

struct QualityCheckMeasurement: Sendable {
    var fileName: String
    var cutPoints: [QualityCheckCutPoint] = []
    /// Active picture inside the coded frame, from cropdetect. Equal to the
    /// full frame when there are no bars.
    var contentX: Int?
    var contentY: Int?
    var contentWidth: Int?
    var contentHeight: Int?
    /// Frames ffmpeg actually decoded, and the duration it actually played.
    var measuredFrames: Int?
    var measuredDurationSeconds: Double?
    /// Frames left after mpdecimate drops duplicates. Lower than
    /// measuredFrames when a lower-rate master was padded up.
    var uniqueFrames: Int?

    var contentAspect: Double? {
        guard let contentWidth, let contentHeight, contentWidth > 0, contentHeight > 0 else { return nil }
        return Double(contentWidth) / Double(contentHeight)
    }

    var measuredFrameRate: Double? {
        guard let measuredFrames, let measuredDurationSeconds, measuredDurationSeconds > 0 else { return nil }
        return Double(measuredFrames) / measuredDurationSeconds
    }

    /// Rate of distinct pictures — 24 for a 24p master padded into a 30p
    /// container, where measuredFrameRate would say 30.
    var uniqueFrameRate: Double? {
        guard let uniqueFrames, let measuredDurationSeconds, measuredDurationSeconds > 0 else { return nil }
        return Double(uniqueFrames) / measuredDurationSeconds
    }
}

struct QualityCheckAnalysisResult: Sendable {
    var findings: [QualityCheckFinding]
    var rawOutputs: [QualityCheckAnalyzerOutput]
    var measurements: [QualityCheckMeasurement] = []
}

struct QualityCheckFormatting {
    static let fallbackFrameRate: Double = 25

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.000" }

        let hours = Int(seconds / 3600)
        let minutes = Int(seconds / 60) % 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds - floor(seconds)) * 1000)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, millis)
        }
        return String(format: "%d:%02d.%03d", minutes, secs, millis)
    }

    static func normalizedFrameRate(_ frameRate: Double) -> Double {
        frameRate.isFinite && frameRate > 0 ? frameRate : fallbackFrameRate
    }

    static func frameIndex(for seconds: Double, frameRate: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return max(0, Int((seconds * normalizedFrameRate(frameRate)).rounded()))
    }

    static func seconds(forFrame frame: Int, frameRate: Double) -> Double {
        Double(max(0, frame)) / normalizedFrameRate(frameRate)
    }

    static func formatFrameTimecode(_ seconds: Double, frameRate: Double) -> String {
        let fps = normalizedFrameRate(frameRate)
        let roundedFPS = max(1, Int(fps.rounded()))
        let totalFrames = frameIndex(for: seconds, frameRate: fps)
        let totalSeconds = totalFrames / roundedFPS
        let frames = totalFrames % roundedFPS
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let secs = totalSeconds % 60

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }

    static func formatFrameDuration(_ seconds: Double, frameRate: Double) -> String {
        let frames = frameIndex(for: seconds, frameRate: frameRate)
        return "\(frames) fr"
    }
}
