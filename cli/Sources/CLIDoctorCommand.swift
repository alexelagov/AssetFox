import Foundation

struct CLIDoctorCommand {
    let pretty: Bool

    static func parse(arguments: [String]) throws -> CLIDoctorCommand {
        var pretty = false
        for argument in arguments {
            switch argument {
            case "--pretty":
                pretty = true
            case "--json":
                break
            default:
                throw CLIUsageError(message: "Unknown doctor option: \(argument)")
            }
        }
        return CLIDoctorCommand(pretty: pretty)
    }

    func run() throws {
        let mediaInfoStatus = MediaInfoLibBridge.runtimeStatus()
        let snapshot = FFmpegRuntimeResolver.snapshot()

        func tool(_ resolution: RuntimeToolResolution) -> [String: Any] {
            var payload: [String: Any] = [
                "available": resolution.isAvailable,
                "source": resolution.source.rawValue
            ]
            payload.setIfPresent("path", resolution.executableURL?.path)
            return payload
        }

        let payload: [String: Any] = [
            "media_info_lib": [
                "loaded": (mediaInfoStatus["loaded"] as? Bool) ?? false,
                "path": (mediaInfoStatus["path"] as? String) ?? "",
                "errors": (mediaInfoStatus["errors"] as? [String]) ?? []
            ],
            "ffmpeg": tool(snapshot.ffmpeg),
            "ffprobe": tool(snapshot.ffprobe)
        ]

        try CLIOutput.emit(
            CLIOutput.envelope(command: "doctor", payload: payload),
            pretty: pretty
        )
    }
}
