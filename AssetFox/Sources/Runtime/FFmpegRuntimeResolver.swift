import Foundation

enum FFmpegTool: String, CaseIterable, Identifiable, Sendable {
    case ffmpeg
    case ffprobe

    var id: String { rawValue }
}

enum RuntimeToolSource: String, Sendable {
    case bundled = "Bundled"
    case homebrew = "Homebrew"
    case usrLocal = "usr/local"
    case missing = "Missing"
}

struct RuntimeToolResolution: Identifiable, Sendable {
    let tool: FFmpegTool
    let executableURL: URL?
    let source: RuntimeToolSource

    var id: String { tool.rawValue }

    var isAvailable: Bool {
        executableURL != nil
    }

    var statusTitle: String {
        isAvailable ? "\(tool.rawValue) Ready" : "\(tool.rawValue) Missing"
    }

    var displayPath: String {
        executableURL?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Not found"
    }
}

struct FFmpegRuntimeSnapshot: Sendable {
    let ffmpeg: RuntimeToolResolution
    let ffprobe: RuntimeToolResolution

    var tools: [RuntimeToolResolution] {
        [ffmpeg, ffprobe]
    }

    var hasAnalyzerRuntime: Bool {
        ffmpeg.isAvailable
    }
}

struct FFmpegRuntimeResolver: Sendable {
    static func snapshot() -> FFmpegRuntimeSnapshot {
        FFmpegRuntimeSnapshot(
            ffmpeg: resolve(.ffmpeg),
            ffprobe: resolve(.ffprobe)
        )
    }

    static func resolve(_ tool: FFmpegTool) -> RuntimeToolResolution {
        for candidate in candidates(for: tool) where FileManager.default.isExecutableFile(atPath: candidate.url.path) {
            return RuntimeToolResolution(tool: tool, executableURL: candidate.url, source: candidate.source)
        }

        return RuntimeToolResolution(tool: tool, executableURL: nil, source: .missing)
    }

    private static func candidates(for tool: FFmpegTool) -> [(url: URL, source: RuntimeToolSource)] {
        var result: [(URL, RuntimeToolSource)] = []

        if let resourceURL = Bundle.main.resourceURL {
            result.append((resourceURL.appendingPathComponent("Tools").appendingPathComponent(tool.rawValue), .bundled))
        }

        result.append((URL(fileURLWithPath: "/opt/homebrew/bin").appendingPathComponent(tool.rawValue), .homebrew))
        result.append((URL(fileURLWithPath: "/usr/local/bin").appendingPathComponent(tool.rawValue), .usrLocal))

        return result
    }
}
