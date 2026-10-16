import Foundation
import zlib

struct CollectReportRow: Sendable {
    var sourcePath: String
    var status: String
    var destinationPath: String
    var reason: String
}

@main
struct CollectMediaXMLParserSecurityTests {
    static func main() async throws {
        try testUnsupportedFCPXMLPathURLsAreSkipped()
        try testSupportedFCPXMLPathURLsAreCollected()
        try testLocalhostAndPercentEncodedPathURLsAreNormalizedBeforeValidation()
        try testGzippedPremiereProjectWithinLimitIsParsed()
        try testGzippedPremiereProjectOverLimitIsRejectedBeforeBuffering()
        try testPlainPremiereProjectOverLimitIsRejected()
        print("CollectMediaXMLParserSecurityTests passed")
        // This @main doubles as the package's whole test entry point (the
        // header comment in Package.swift says why there is no testTarget).
        PixelFormatBitDepthTests.run()
        try await IngestCopierTests.run()
    }

    private static func testUnsupportedFCPXMLPathURLsAreSkipped() throws {
        let unsupported = [
            "file:///etc/hosts",
            "file:///tmp/private.pem",
            "file:///tmp/private.key",
            "file:///tmp/project.env",
            "file:///tmp/cache.sqlite",
            "file:///tmp/readme.txt",
            "file:///tmp/no_extension"
        ]

        let result = try parse(pathURLs: unsupported)
        assertEqual(result.entries.count, 0, "Unsupported FCP XML pathurl values must not become collect entries")
        assertEqual(result.parserRows.count, unsupported.count, "Each unsupported FCP XML pathurl should create a skipped report row")

        for row in result.parserRows {
            assertEqual(row.status, "skipped", "Unsupported path row should be skipped")
            assertEqual(row.reason, "unsupported media extension ignored", "Unsupported path row should explain allowlist filtering")
        }
    }

    private static func testSupportedFCPXMLPathURLsAreCollected() throws {
        let supported = [
            "file:///Volumes/Rushes/clip.mov",
            "file:///Volumes/Rushes/card.mxf",
            "file:///Volumes/Rushes/audio.wav",
            "file:///Volumes/Rushes/frame.png",
            "file:///Volumes/Rushes/photo.jpeg",
            "file:///Volumes/Rushes/scan.tiff"
        ]

        let result = try parse(pathURLs: supported)
        assertEqual(result.entries.count, supported.count, "Supported media pathurl values should become collect entries")
        assertEqual(result.parserRows.count, 0, "Supported media pathurl values should not create parser warnings")

        let extensions = Set(result.entries.map(\.fileExtension))
        assertEqual(extensions, ["mov", "mxf", "wav", "png", "jpeg", "tiff"], "Collected entries should preserve supported canonical extensions")
    }

    private static func testLocalhostAndPercentEncodedPathURLsAreNormalizedBeforeValidation() throws {
        let result = try parse(pathURLs: [
            "file://localhost/Volumes/Rushes/Localhost%20Clip.mov",
            "file:///Volumes/Rushes/Encoded%20Folder/Shot%2001.mxf",
            "file:///Volumes/Rushes/Encoded%20Folder/secret%20file.pem"
        ])

        assertEqual(result.entries.count, 2, "Localhost and percent-encoded media paths should pass after normalization")
        assertEqual(result.parserRows.count, 1, "Percent-encoded unsupported paths should be skipped after normalization")

        let paths = Set(result.entries.map(\.sourcePath))
        assert(paths.contains("/Volumes/Rushes/Localhost Clip.mov"), "file://localhost path should normalize to a local file path")
        assert(paths.contains("/Volumes/Rushes/Encoded Folder/Shot 01.mxf"), "Percent-encoded media path should be decoded before validation")

        let skipped = try unwrap(result.parserRows.first, "Expected one skipped unsupported path")
        assertEqual(skipped.sourcePath, "/Volumes/Rushes/Encoded Folder/secret file.pem", "Skipped report row should use normalized decoded path")
    }

    // AF-11: a gzipped .prproj is inflated under a byte ceiling, so a small
    // crafted project cannot expand without bound. The limit is exact: a
    // project of exactly `maximumXMLBytes` parses, one byte more does not.
    private static func testGzippedPremiereProjectWithinLimitIsParsed() throws {
        // Padded so the compressed file is far smaller than its XML: the
        // parser also refuses a file whose on-disk size exceeds the limit.
        let xml = premiereProjectXML(padding: 512 * 1024)
        let url = try writeTemporaryProject(xml, gzipped: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let parser = CollectMediaPremiereProjectParser(maximumXMLBytes: xml.utf8.count)
        let result = try parser.parse(projectURL: url)
        assertEqual(result.entries.map(\.sourcePath), ["/Volumes/Rushes/clip.mov"], "A gzipped project at the limit should still be parsed")
    }

    private static func testGzippedPremiereProjectOverLimitIsRejectedBeforeBuffering() throws {
        // Highly compressible padding: the .prproj on disk stays tiny while
        // its XML runs past the 64 KiB read buffer several times over.
        let xml = premiereProjectXML(padding: 512 * 1024)
        let url = try writeTemporaryProject(xml, gzipped: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let compressedSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        assert(compressedSize < 64 * 1024, "The fixture should be a small file that inflates past the limit")

        let limit = 256 * 1024
        assertTooLarge(limit: limit, "A gzipped project whose XML exceeds the limit must be rejected") {
            try CollectMediaPremiereProjectParser(maximumXMLBytes: limit).parse(projectURL: url)
        }
        assertTooLarge(limit: xml.utf8.count - 1, "A gzipped project one byte over the limit must be rejected") {
            try CollectMediaPremiereProjectParser(maximumXMLBytes: xml.utf8.count - 1).parse(projectURL: url)
        }
    }

    private static func testPlainPremiereProjectOverLimitIsRejected() throws {
        let xml = premiereProjectXML(padding: 0)
        let url = try writeTemporaryProject(xml, gzipped: false)
        defer { try? FileManager.default.removeItem(at: url) }

        let atLimit = try CollectMediaPremiereProjectParser(maximumXMLBytes: xml.utf8.count).parse(projectURL: url)
        assertEqual(atLimit.entries.count, 1, "An uncompressed project at the limit should still be parsed")

        assertTooLarge(limit: xml.utf8.count - 1, "An uncompressed project over the limit must be rejected") {
            try CollectMediaPremiereProjectParser(maximumXMLBytes: xml.utf8.count - 1).parse(projectURL: url)
        }
    }

    private static func premiereProjectXML(padding: Int) -> String {
        let filler = padding > 0 ? "<!--\(String(repeating: "a", count: padding))-->" : ""
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><PremiereData Version=\"3\">\(filler)<Media><ActualMediaFilePath>/Volumes/Rushes/clip.mov</ActualMediaFilePath></Media></PremiereData>"
    }

    private static func writeTemporaryProject(_ xml: String, gzipped: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("prproj")
        guard gzipped else {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        guard let file = gzopen(url.path, "wb") else {
            fatalError("Could not create gzipped fixture at \(url.path)")
        }
        let bytes = Array(xml.utf8)
        let written = bytes.withUnsafeBytes { rawBuffer in
            gzwrite(file, rawBuffer.baseAddress, UInt32(rawBuffer.count))
        }
        let closed = gzclose(file)
        assertEqual(Int(written), bytes.count, "The gzipped fixture should be written in full")
        assertEqual(closed, Z_OK, "The gzipped fixture should close cleanly")
        return url
    }

    private static func assertTooLarge(limit: Int, _ message: String, _ body: () throws -> ParsedCollectMediaDocument) {
        do {
            let result = try body()
            fatalError("\(message). Expected projectTooLarge, got \(result.entries.count) entries")
        } catch let error as PremiereProjectParserError {
            assertEqual(error, .projectTooLarge(limitBytes: limit), message)
        } catch {
            fatalError("\(message). Expected projectTooLarge, got \(error)")
        }
    }

    private static func parse(pathURLs: [String]) throws -> ParsedCollectMediaDocument {
        let body = pathURLs.map { "<file><pathurl>\(escapeXML($0))</pathurl></file>" }.joined()
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><xmeml><sequence><media>\(body)</media></sequence></xmeml>"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try CollectMediaXMLParser().parse(xmlURL: url)
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fatalError("\(message). Expected \(expected), got \(actual)")
        }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { fatalError(message) }
        return value
    }
}
