import Foundation

enum CLIOutput {
    static let schemaVersion = "assetfox.cli/v1"
    static let cliVersion = "0.1.0"

    static func envelope(command: String, payload: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [
            "schema": schemaVersion,
            "cli_version": cliVersion,
            "command": command
        ]
        for (key, value) in payload {
            body[key] = value
        }
        return body
    }

    static func emit(_ object: [String: Any], pretty: Bool) throws {
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func progress(_ message: String) {
        FileHandle.standardError.write(Data("progress: \(message)\n".utf8))
    }

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}

struct CLIUsageError: Error {
    let message: String
}

extension Dictionary where Key == String, Value == Any {
    mutating func setIfPresent(_ key: String, _ value: Any?) {
        if let value {
            self[key] = value
        }
    }
}
