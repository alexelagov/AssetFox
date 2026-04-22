import Foundation
import zlib

struct ParsedCollectMediaDocument {
    var entries: [CollectMediaEntry]
    var parserRows: [CollectReportRow]
}

struct CollectMediaXMLParser {
    func parse(xmlURL: URL) throws -> ParsedCollectMediaDocument {
        let data = try Data(contentsOf: xmlURL)
        let document = try XMLDocument(data: data, options: [])

        let pathNodes = try document.nodes(forXPath: "//*[local-name()='pathurl']")
        var entriesByPath: [String: CollectMediaEntry] = [:]
        var parserRows: [CollectReportRow] = []

        for node in pathNodes {
            guard let element = node as? XMLElement else { continue }
            let rawURL = (element.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawURL.isEmpty else { continue }

            guard let sourcePath = pathFromFileURL(rawURL) else {
                parserRows.append(CollectReportRow(
                    sourcePath: rawURL,
                    status: "skipped",
                    destinationPath: "",
                    reason: "non-file or unsupported URL"
                ))
                continue
            }

            let fileElement = nearestFileAncestor(from: element)
            let basename = URL(fileURLWithPath: sourcePath).lastPathComponent
            let fileExtension = URL(fileURLWithPath: sourcePath).pathExtension.lowercased()
            let entry = CollectMediaEntry(
                sourcePath: sourcePath,
                basename: basename,
                fileExtension: fileExtension,
                expectedTimecodeStart: fileElement.flatMap(findTimecodeStart),
                expectedDurationSeconds: fileElement.flatMap(findExpectedDuration),
                expectedSizeBytes: nil
            )

            if let existing = entriesByPath[sourcePath] {
                entriesByPath[sourcePath] = merge(existing: existing, incoming: entry)
            } else {
                entriesByPath[sourcePath] = entry
            }
        }

        return ParsedCollectMediaDocument(
            entries: Array(entriesByPath.values).sorted { $0.sourcePath < $1.sourcePath },
            parserRows: parserRows
        )
    }

    private func pathFromFileURL(_ rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL), components.scheme?.lowercased() == "file" else {
            return nil
        }

        let host = (components.host ?? "").lowercased()
        var path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        if !host.isEmpty, host != "localhost" {
            path = "/\(components.host ?? "")\(path)"
        }

        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func nearestFileAncestor(from element: XMLNode) -> XMLElement? {
        var currentNode = element.parent
        while let current = currentNode {
            if localName(of: current) == "file" {
                return current as? XMLElement
            }
            currentNode = current.parent
        }
        return nil
    }

    private func findTimecodeStart(in fileElement: XMLElement) -> String? {
        for node in fileElement.descendants {
            guard localName(of: node) == "timecode" else { continue }
            if let nested = firstDescendantValue(in: node, names: ["string", "start", "timecode"]), nested.contains(":") {
                return nested
            }
            if let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), text.contains(":") {
                return text
            }
        }
        return nil
    }

    private func findExpectedDuration(in fileElement: XMLElement) -> Double? {
        let timebase = fileElement.descendants
            .filter { localName(of: $0) == "timebase" }
            .compactMap { node in
                (node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .compactMap(Double.init)
            .first { $0 > 0 }

        for node in fileElement.descendants where localName(of: node) == "duration" {
            let raw = (node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(raw) else { continue }
            if let timebase {
                return value / timebase
            }
            if raw.contains(".") {
                return value
            }
        }
        return nil
    }

    private func firstDescendantValue(in node: XMLNode, names: Set<String>) -> String? {
        for descendant in node.descendants where names.contains(localName(of: descendant)) {
            if let value = descendant.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func localName(of node: XMLNode?) -> String {
        (node?.name?.split(separator: ":").last).map(String.init)?.lowercased() ?? ""
    }

    private func merge(existing: CollectMediaEntry, incoming: CollectMediaEntry) -> CollectMediaEntry {
        CollectMediaEntry(
            id: existing.id,
            sourcePath: existing.sourcePath,
            basename: existing.basename,
            fileExtension: existing.fileExtension,
            expectedTimecodeStart: existing.expectedTimecodeStart ?? incoming.expectedTimecodeStart,
            expectedDurationSeconds: existing.expectedDurationSeconds ?? incoming.expectedDurationSeconds,
            expectedSizeBytes: existing.expectedSizeBytes ?? incoming.expectedSizeBytes
        )
    }
}

struct CollectMediaPremiereProjectParser {
    func parse(projectURL: URL) throws -> ParsedCollectMediaDocument {
        let data = try projectXMLData(from: projectURL)
        let document = try XMLDocument(data: data, options: [])
        let candidates = candidatePathValues(in: document)

        var entriesByPath: [String: CollectMediaEntry] = [:]
        var parserRows: [CollectReportRow] = []

        for candidate in candidates {
            switch normalizedPath(from: candidate.value) {
            case .filePath(let sourcePath):
                guard isLikelyMediaPath(sourcePath) else { continue }

                let sourceURL = URL(fileURLWithPath: sourcePath)
                let entry = CollectMediaEntry(
                    sourcePath: sourceURL.standardizedFileURL.path,
                    basename: sourceURL.lastPathComponent,
                    fileExtension: sourceURL.pathExtension.lowercased()
                )

                entriesByPath[entry.sourcePath] = entriesByPath[entry.sourcePath].map {
                    merge(existing: $0, incoming: entry)
                } ?? entry

            case .unsupportedPath(let rawPath):
                guard isLikelyMediaPath(rawPath) else { continue }
                parserRows.append(CollectReportRow(
                    sourcePath: rawPath,
                    status: "skipped",
                    destinationPath: "",
                    reason: "Premiere project path is not a macOS file path"
                ))

            case .none:
                continue
            }
        }

        return ParsedCollectMediaDocument(
            entries: Array(entriesByPath.values).sorted { $0.sourcePath < $1.sourcePath },
            parserRows: parserRows
        )
    }

    private func projectXMLData(from projectURL: URL) throws -> Data {
        let data = try Data(contentsOf: projectURL)
        guard data.starts(with: [0x1f, 0x8b]) else {
            return data
        }
        return try gunzippedData(from: projectURL)
    }

    private func gunzippedData(from projectURL: URL) throws -> Data {
        guard let file = gzopen(projectURL.path, "rb") else {
            throw PremiereProjectParserError.unreadableCompressedProject
        }
        defer { gzclose(file) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let bufferSize = UInt32(buffer.count)
            let readCount = buffer.withUnsafeMutableBytes { bufferPointer in
                gzread(file, bufferPointer.baseAddress, bufferSize)
            }

            if readCount > 0 {
                output.append(contentsOf: buffer.prefix(Int(readCount)))
            } else if readCount == 0 {
                break
            } else {
                throw PremiereProjectParserError.unreadableCompressedProject
            }
        }

        return output
    }

    private func candidatePathValues(in document: XMLDocument) -> [(value: String, context: String)] {
        guard let root = document.rootElement() else { return [] }
        var values: [(value: String, context: String)] = []

        for node in [root] + root.descendants {
            guard let element = node as? XMLElement else { continue }
            let elementName = localName(of: element)

            if isPathLikeName(elementName),
               !hasElementChildren(element),
               let value = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                values.append((value, elementName))
            }

            for attribute in element.attributes ?? [] {
                let attributeName = localName(of: attribute)
                guard isPathLikeName(attributeName) else { continue }
                if let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    values.append((value, attributeName))
                }
            }
        }

        return values
    }

    private func hasElementChildren(_ element: XMLElement) -> Bool {
        element.children?.contains { $0 is XMLElement } == true
    }

    private func isPathLikeName(_ name: String) -> Bool {
        name.contains("path")
            || name.contains("url")
            || name == "filename"
            || name == "file"
            || name.contains("mediafile")
    }

    private func normalizedPath(from rawValue: String) -> ParsedPremiereProjectPath {
        let trimmed = rawValue
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))

        guard !trimmed.isEmpty, trimmed.count < 4096 else { return .none }

        if let fileURLPath = pathFromFileURL(trimmed) {
            return .filePath(fileURLPath)
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if let fileURLPath = pathFromFileURL(decoded) {
            return .filePath(fileURLPath)
        }

        if decoded.hasPrefix("/") {
            return .filePath(URL(fileURLWithPath: decoded).standardizedFileURL.path)
        }

        if decoded.hasPrefix("~/") {
            let expanded = NSString(string: decoded).expandingTildeInPath
            return .filePath(URL(fileURLWithPath: expanded).standardizedFileURL.path)
        }

        if decoded.hasPrefix("Volumes/") || decoded.hasPrefix("Users/") {
            return .filePath(URL(fileURLWithPath: "/" + decoded).standardizedFileURL.path)
        }

        if isWindowsPath(decoded) {
            return .unsupportedPath(decoded)
        }

        return .none
    }

    private func pathFromFileURL(_ rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL), components.scheme?.lowercased() == "file" else {
            return nil
        }

        let host = (components.host ?? "").lowercased()
        var path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        if !host.isEmpty, host != "localhost" {
            path = "/\(components.host ?? "")\(path)"
        }

        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isWindowsPath(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z]:\\"#, options: .regularExpression) != nil
            || value.hasPrefix("\\\\")
    }

    private func isLikelyMediaPath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return mediaExtensions.contains(ext)
    }

    private func merge(existing: CollectMediaEntry, incoming: CollectMediaEntry) -> CollectMediaEntry {
        CollectMediaEntry(
            id: existing.id,
            sourcePath: existing.sourcePath,
            basename: existing.basename,
            fileExtension: existing.fileExtension,
            expectedTimecodeStart: existing.expectedTimecodeStart ?? incoming.expectedTimecodeStart,
            expectedDurationSeconds: existing.expectedDurationSeconds ?? incoming.expectedDurationSeconds,
            expectedSizeBytes: existing.expectedSizeBytes ?? incoming.expectedSizeBytes
        )
    }

    private func localName(of node: XMLNode?) -> String {
        (node?.name?.split(separator: ":").last).map(String.init)?.lowercased() ?? ""
    }

    private var mediaExtensions: Set<String> {
        [
            "3gp", "aaf", "aac", "aif", "aiff", "ari", "arx", "asf", "avi",
            "braw", "crm", "dng", "dpx", "exr", "flac", "gif", "heic", "heif",
            "jpeg", "jpg", "m2t", "m2ts", "m4a", "m4v", "mkv", "mov", "mp3",
            "mp4", "mpeg", "mpg", "mts", "mxf", "omf", "png", "psd", "r3d",
            "tga", "tif", "tiff", "wav", "webm", "wma", "wmv"
        ]
    }
}

private enum ParsedPremiereProjectPath {
    case filePath(String)
    case unsupportedPath(String)
    case none
}

private enum PremiereProjectParserError: LocalizedError {
    case unreadableCompressedProject

    var errorDescription: String? {
        switch self {
        case .unreadableCompressedProject:
            return "The Premiere project is compressed, but AssetFox could not read its XML payload."
        }
    }
}

private extension XMLNode {
    var descendants: [XMLNode] {
        let childNodes = children ?? []
        return childNodes + childNodes.flatMap(\.descendants)
    }
}
