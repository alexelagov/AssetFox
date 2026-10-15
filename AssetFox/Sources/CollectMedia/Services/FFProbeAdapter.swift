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
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drained while ffprobe runs: -show_streams on an MXF with many tracks
        // is well past the 64K pipe buffer, and waiting for exit first left
        // ffprobe blocked on write and this call blocked on wait, for good.
        let outSink = ByteSink(outputPipe.fileHandleForReading)
        let errSink = ByteSink(errorPipe.fileHandleForReading)
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            outSink.finish()
            errSink.finish()
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }
        outSink.finish()
        errSink.finish()

        guard process.terminationStatus == 0 else {
            return FFProbeMetadata(durationSeconds: nil, timecodeStart: nil)
        }

        let data = outSink.bytes
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
        FFmpegRuntimeResolver.resolve(.ffprobe).executableURL
    }
}
