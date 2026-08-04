import Foundation

struct CLIQualityCheckCommand {
    let paths: [String]
    let referencePath: String?
    let toleranceFrames: Int
    let includeRaw: Bool
    let pretty: Bool

    static func parse(arguments: [String]) throws -> CLIQualityCheckCommand {
        var paths: [String] = []
        var referencePath: String?
        var toleranceFrames = 2
        var includeRaw = false
        var pretty = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--reference":
                index += 1
                guard index < arguments.count else {
                    throw CLIUsageError(message: "--reference needs a file path value.")
                }
                referencePath = arguments[index]
            case "--tolerance-frames":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value >= 0 else {
                    throw CLIUsageError(message: "--tolerance-frames needs a non-negative integer value.")
                }
                toleranceFrames = value
            case "--include-raw":
                includeRaw = true
            case "--pretty":
                pretty = true
            case "--json":
                break
            default:
                if argument.hasPrefix("--") {
                    throw CLIUsageError(message: "Unknown qc option: \(argument)")
                }
                paths.append(argument)
            }
            index += 1
        }

        guard !paths.isEmpty else {
            throw CLIUsageError(message: "qc needs at least one file path.")
        }

        return CLIQualityCheckCommand(
            paths: paths,
            referencePath: referencePath,
            toleranceFrames: toleranceFrames,
            includeRaw: includeRaw,
            pretty: pretty
        )
    }

    func run() async throws {
        var allPaths = paths
        if let referencePath, !allPaths.contains(referencePath) {
            allPaths.insert(referencePath, at: 0)
        }

        let loader = CLIMediaItemLoader()
        var items: [QualityCheckVideoItem] = []
        var loadWarnings: [String] = []
        var missing: [[String: Any]] = []

        for path in allPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                missing.append(["path": url.path, "error": "File does not exist."])
                continue
            }
            let loaded = await loader.load(url: url)
            items.append(loaded.item)
            loadWarnings.append(contentsOf: loaded.warnings.map { "\(url.lastPathComponent): \($0)" })
        }

        guard !items.isEmpty else {
            throw CLIUsageError(message: "None of the qc input files exist.")
        }

        let referenceItemID: UUID?
        if let referencePath {
            let referenceURL = URL(fileURLWithPath: referencePath).standardizedFileURL
            guard let match = items.first(where: { $0.url.path == referenceURL.path }) else {
                throw CLIUsageError(message: "Reference file could not be loaded: \(referencePath)")
            }
            referenceItemID = match.id
        } else {
            referenceItemID = nil
        }

        let analyzer = QualityCheckAnalyzer()
        let result = try await analyzer.analyze(
            items: items,
            referenceItemID: referenceItemID,
            toleranceFrames: toleranceFrames
        ) { status in
            CLIOutput.progress(status)
        }

        var payload: [String: Any] = [
            "tolerance_frames": toleranceFrames,
            "files": items.map { item in
                var file: [String: Any] = [
                    "path": item.url.path,
                    "file_name": item.name,
                    "file_size_bytes": item.fileSize
                ]
                if item.durationSeconds > 0 {
                    file["duration_seconds"] = item.durationSeconds
                }
                if item.nominalFrameRate > 0 {
                    file["nominal_frame_rate"] = item.nominalFrameRate
                }
                if item.naturalSize.width > 0, item.naturalSize.height > 0 {
                    file["width"] = Int(item.naturalSize.width)
                    file["height"] = Int(item.naturalSize.height)
                }
                if item.id == referenceItemID {
                    file["is_reference"] = true
                }
                return file
            },
            "findings": result.findings.map(finding(from:)),
            "measurements": result.measurements.map(measurement(from:))
        ]

        if !missing.isEmpty {
            payload["missing_files"] = missing
        }
        if !loadWarnings.isEmpty {
            payload["warnings"] = loadWarnings
        }
        if includeRaw {
            payload["raw_outputs"] = result.rawOutputs.map {
                ["file_name": $0.fileName, "raw_output": $0.rawOutput]
            }
        }

        try CLIOutput.emit(
            CLIOutput.envelope(command: "qc", payload: payload),
            pretty: pretty
        )
    }

    private func finding(from finding: QualityCheckFinding) -> [String: Any] {
        var payload: [String: Any] = [
            "severity": finding.severity.rawValue.lowercased(),
            "kind": kindSlug(finding.kind),
            "file_name": finding.fileName,
            "time_seconds": finding.timeSeconds,
            "message": finding.message
        ]
        payload.setIfPresent("duration_seconds", finding.durationSeconds)
        payload.setIfPresent("details", finding.details)
        return payload
    }

    /// Measured facts about the file, for a caller that wants to compare them
    /// against a delivery spec. Absent keys mean "not measured" — never 0.
    private func measurement(from measurement: QualityCheckMeasurement) -> [String: Any] {
        var payload: [String: Any] = ["file_name": measurement.fileName]
        if let x = measurement.contentX,
           let y = measurement.contentY,
           let width = measurement.contentWidth,
           let height = measurement.contentHeight {
            payload["content_bounds"] = ["x": x, "y": y, "width": width, "height": height]
        }
        payload.setIfPresent("content_aspect", measurement.contentAspect)
        payload.setIfPresent("measured_frames", measurement.measuredFrames)
        payload.setIfPresent("measured_duration_seconds", measurement.measuredDurationSeconds)
        payload.setIfPresent("measured_frame_rate", measurement.measuredFrameRate)
        payload.setIfPresent("unique_frames", measurement.uniqueFrames)
        payload.setIfPresent("unique_frame_rate", measurement.uniqueFrameRate)
        if !measurement.cutPoints.isEmpty {
            payload["cut_points"] = measurement.cutPoints.map {
                ["time_seconds": $0.timeSeconds, "score": $0.score]
            }
        }
        return payload
    }

    private func kindSlug(_ kind: QualityCheckFindingKind) -> String {
        switch kind {
        case .blackFrame: return "black_frame"
        case .freezeFrame: return "freeze_frame"
        case .cutMismatch: return "cut_mismatch"
        case .runtime: return "runtime"
        }
    }
}
