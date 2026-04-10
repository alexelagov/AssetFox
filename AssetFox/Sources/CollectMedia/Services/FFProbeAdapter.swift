import Foundation

struct FFProbeMetadata: Sendable {
    var durationSeconds: Double?
    var timecodeStart: String?
}

struct FFProbeAdapter: Sendable {
    let executableURL: URL?

    init(executableURL: URL? = FFProbeAdapter.locateExecutable()) {
        self.executableURL = executableURL
    }

    var isAvailable: Bool {
        executableURL != nil
    }

    func probeMedia(at url: URL) -> FFProbeMetadata {
        guard let executableURL else {
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_entries", "format=duration:format_tags=timecode",
            "-i", url.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }

        guard process.terminationStatus == 0 else {
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let format = object["format"] as? [String: Any]
        else {
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }

        let duration = (format["duration"] as? String).flatMap(Double.init)
        let tags = format["tags"] as? [String: Any]
        let timecode = tags?["timecode"] as? String
        return FFProbeMetadata(durationSeconds: duration, timecodeStart: timecode?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func locateExecutable() -> URL? {
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for folder in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent("ffprobe")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        let fallbackPaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe"
        ]
        for path in fallbackPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
