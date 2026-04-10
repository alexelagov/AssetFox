import Foundation

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

private extension XMLNode {
    var descendants: [XMLNode] {
        let childNodes = children ?? []
        return childNodes + childNodes.flatMap(\.descendants)
    }
}
