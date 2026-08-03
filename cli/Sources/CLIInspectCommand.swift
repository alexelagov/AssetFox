import Foundation

struct CLIInspectCommand {
    let paths: [String]
    let pretty: Bool

    static func parse(arguments: [String]) throws -> CLIInspectCommand {
        var paths: [String] = []
        var pretty = false

        for argument in arguments {
            switch argument {
            case "--pretty":
                pretty = true
            case "--json":
                break
            default:
                if argument.hasPrefix("--") {
                    throw CLIUsageError(message: "Unknown inspect option: \(argument)")
                }
                paths.append(argument)
            }
        }

        guard !paths.isEmpty else {
            throw CLIUsageError(message: "inspect needs at least one file path.")
        }

        return CLIInspectCommand(paths: paths, pretty: pretty)
    }

    func run() async throws {
        let inspector = MediaInfoInspector()
        let loader = CLIMediaItemLoader()
        let encoder = CLIPassportEncoder()
        var files: [[String: Any]] = []

        for (index, path) in paths.enumerated() {
            CLIOutput.progress("Inspecting \((path as NSString).lastPathComponent) (\(index + 1) of \(paths.count))")
            let url = URL(fileURLWithPath: path).standardizedFileURL

            guard FileManager.default.fileExists(atPath: url.path) else {
                files.append(encoder.unreadablePassport(path: url.path, reason: "File does not exist."))
                continue
            }

            let inspection = await inspector.inspect(url: url)
            let loaded = await loader.load(url: url)
            files.append(
                encoder.passport(
                    path: url.path,
                    inspection: inspection,
                    item: loaded.item,
                    loaderWarnings: loaded.warnings
                )
            )
        }

        try CLIOutput.emit(
            CLIOutput.envelope(command: "inspect", payload: ["files": files]),
            pretty: pretty
        )
    }
}
