import Foundation

// AF-01: compile the actual app copier through Tests/Compiled. All files are
// tiny synthetic data in a fresh temporary directory; no GUI or media tools.
enum IngestCopierTests {
    static func run() async throws {
        try await testVerifiedOverwritePublishesOnlyAfterHashing()
        try await testMissingSourceDuringVerificationPreservesOriginal()
        try await testChangedSourceDuringVerificationPreservesOriginal()
        try await testDamagedStagingPreservesOriginal()
        try await testCancellation(at: "Verifying SHA-256")
        try await testCancellation(at: "Copying file")
        try await testCancellation(at: "Comparing existing destination file")
        try await testFailedCopyPreservesOriginal()
        try await testOverwriteWithoutVerification()
        try await testSkipAndMatchingExisting()
        try await testNewDestination()
        print("IngestCopierTests passed (12 synthetic scenarios)")
    }

    private struct Fixture: Sendable {
        let root: URL
        let sourceRoot: URL
        let destinationRoot: URL
        let source: URL
        let destination: URL
        let original = Data("ORIGINAL".utf8)
        let replacement = Data("REPLACED".utf8)

        init(existing: Bool = true) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("AssetFoxIngestTests-\(UUID().uuidString)")
            sourceRoot = root.appendingPathComponent("source")
            destinationRoot = root.appendingPathComponent("destination")
            source = sourceRoot.appendingPathComponent("shot.mov")
            destination = destinationRoot.appendingPathComponent("shot.mov")
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            try replacement.write(to: source)
            if existing { try original.write(to: destination) }
        }

        func copy(
            mode: IngestConflictMode = .overwriteExisting,
            verify: Bool = true,
            progress: @escaping @Sendable (IngestCopyProgress) async -> Void = { _ in }
        ) async throws -> IngestCopyResult {
            try await IngestCopier().copyRecursively(
                sourceURL: sourceRoot, destinationURL: destinationRoot,
                conflictMode: mode, verificationEnabled: verify,
                preserveFolderStructure: true, progress: progress
            )
        }

        func checkDestination(_ expected: Data) {
            precondition((try? Data(contentsOf: destination)) == expected, "Destination bytes unexpectedly changed")
        }

        func stagingFiles() -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: destinationRoot, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(".assetfox-partial-") }
        }

        func checkClean() { precondition(stagingFiles().isEmpty, "Staging file leaked") }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private static func testVerifiedOverwritePublishesOnlyAfterHashing() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let result = try await f.copy { p in
            if p.detail == "Verifying SHA-256" {
                f.checkDestination(f.original)
                precondition(f.stagingFiles().count == 1)
            } else if p.detail == "Verification passed" {
                f.checkDestination(f.replacement)
                f.checkClean()
            }
        }
        precondition(result.copiedFiles == 1 && result.verifiedFiles == 1 && result.verificationFailureCount == 0)
        f.checkDestination(f.replacement)
        f.checkClean()
        print("PASS verified overwrite: ORIGINAL until SHA success, then REPLACED")
    }

    private static func testMissingSourceDuringVerificationPreservesOriginal() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let result = try await f.copy { p in
            if p.detail == "Verifying SHA-256" {
                try? FileManager.default.removeItem(at: f.source)
            }
        }
        precondition(result.verifiedFiles == 0 && result.verificationFailureCount == 1)
        f.checkDestination(f.original)
        f.checkClean()
        print("PASS source removed at SHA: ORIGINAL retained, failed verification recorded")
    }

    private static func testChangedSourceDuringVerificationPreservesOriginal() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let result = try await f.copy { p in
            if p.detail == "Verifying SHA-256" {
                try? Data("MUTATION".utf8).write(to: f.source)
            }
        }
        precondition(result.mismatchCount == 1 && result.verifiedFiles == 0)
        precondition(result.verificationRecords.count == 1)
        if case .mismatch = result.verificationRecords[0].state {} else { preconditionFailure("Expected mismatch record") }
        f.checkDestination(f.original)
        f.checkClean()
        print("PASS source changed at SHA: mismatch recorded, ORIGINAL retained")
    }

    private static func testDamagedStagingPreservesOriginal() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let result = try await f.copy { p in
            if p.detail == "Verifying SHA-256", let stage = f.stagingFiles().first {
                try? Data("DAMAGED!".utf8).write(to: stage)
            }
        }
        precondition(result.mismatchCount == 1 && result.verifiedFiles == 0)
        f.checkDestination(f.original)
        f.checkClean()
        print("PASS staging corruption: mismatch recorded, ORIGINAL retained")
    }

    private static func testCancellation(at detail: String) async throws {
        let f = try Fixture()
        defer { f.remove() }
        // Cancel a child task so later scenarios keep a fresh cancellation state.
        let task = Task {
            try await f.copy { p in
                if p.detail == detail {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await task.value
            preconditionFailure("Cancelled ingest must throw CancellationError")
        } catch is CancellationError {}
        f.checkDestination(f.original)
        f.checkClean()
        print("PASS cancellation at \(detail): cancellation propagated, ORIGINAL retained")
    }

    private static func testFailedCopyPreservesOriginal() async throws {
        let f = try Fixture()
        defer { f.remove() }
        do {
            _ = try await f.copy { p in
                if p.detail == "Copying file" { try? FileManager.default.removeItem(at: f.source) }
            }
            preconditionFailure("Missing copy source must produce the existing fatal source error")
        } catch {
            guard let snapshot = (error as NSError).userInfo["partialSnapshot"] as? IngestPartialRunSnapshot else { throw error }
            precondition(snapshot.copiedFiles == 0 && snapshot.verifiedFiles == 0 && snapshot.verificationFailureCount == 1)
        }
        f.checkDestination(f.original)
        f.checkClean()
        print("PASS missing source at copy: ORIGINAL retained")
    }

    private static func testOverwriteWithoutVerification() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let result = try await f.copy(verify: false)
        precondition(result.copiedFiles == 1 && result.verifiedFiles == 0 && result.verificationFailureCount == 0)
        if case .copiedWithoutVerification = result.verificationRecords[0].state {} else { preconditionFailure("Expected unverified record") }
        f.checkDestination(f.replacement)
        f.checkClean()
        print("PASS explicit verification disabled: publishes complete copy with unverified record")
    }

    private static func testSkipAndMatchingExisting() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let different = try await f.copy(mode: .skipExisting)
        precondition(different.copiedFiles == 0 && different.verificationFailureCount == 1)
        f.checkDestination(f.original)
        try f.replacement.write(to: f.destination)
        let matching = try await f.copy()
        precondition(matching.copiedFiles == 0 && matching.skippedFiles == 1)
        f.checkDestination(f.replacement)
        f.checkClean()
        print("PASS skip differing existing / skip checksum match")
    }

    private static func testNewDestination() async throws {
        let f = try Fixture(existing: false)
        defer { f.remove() }
        let result = try await f.copy()
        precondition(result.copiedFiles == 1 && result.verifiedFiles == 1)
        f.checkDestination(f.replacement)
        f.checkClean()
        print("PASS new destination: normal copy and verification")
    }
}
