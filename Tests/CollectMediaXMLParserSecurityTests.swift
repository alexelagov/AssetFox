import Foundation

struct CollectReportRow: Sendable {
    var sourcePath: String
    var status: String
    var destinationPath: String
    var reason: String
}

@main
struct CollectMediaXMLParserSecurityTests {
    static func main() throws {
        try testUnsupportedFCPXMLPathURLsAreSkipped()
        try testSupportedFCPXMLPathURLsAreCollected()
        try testLocalhostAndPercentEncodedPathURLsAreNormalizedBeforeValidation()
        print("CollectMediaXMLParserSecurityTests passed")
        // This @main doubles as the package's whole test entry point (the
        // header comment in Package.swift says why there is no testTarget).
        PixelFormatBitDepthTests.run()
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
