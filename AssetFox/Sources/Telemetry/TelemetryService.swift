import Foundation
import OSLog

enum TelemetryEventName: String, Sendable {
    case appLaunched = "app_launched"
    case sectionOpened = "section_opened"
    case qcFilesAdded = "qc_files_added"
    case qcAnalysisStarted = "qc_analysis_started"
    case qcAnalysisCompleted = "qc_analysis_completed"
    case qcAnalysisFailed = "qc_analysis_failed"
    case duplicateScanStarted = "duplicate_scan_started"
    case duplicateScanCompleted = "duplicate_scan_completed"
    case collectMediaStarted = "collect_media_started"
    case collectMediaCompleted = "collect_media_completed"
    case ingestStarted = "ingest_started"
    case ingestCompleted = "ingest_completed"
    case mediaInfoFilesAdded = "media_info_files_added"
    case mediaInfoExported = "media_info_exported"
}

enum TelemetryValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

struct TelemetryContext: Codable, Sendable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let processorArch: String
    let anonymousInstallationID: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case macOSVersion = "macos_version"
        case processorArch = "processor_arch"
        case anonymousInstallationID = "anonymous_installation_id"
        case timestamp
    }
}

struct TelemetryEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let event: String
    let properties: [String: TelemetryValue]
    let context: TelemetryContext
}

actor TelemetryService {
    static let shared = TelemetryService()

    private enum Keys {
        static let analyticsEnabled = "assetfox.telemetry.analyticsEnabled"
        static let installationID = "assetfox.telemetry.installationID"
        static let queue = "assetfox.telemetry.queue"
        static let endpointURL = "assetfox.telemetry.endpointURL"
    }

    private let logger = Logger(subsystem: "com.postprod.assetfox", category: "Telemetry")
    private let maxQueuedEvents = 500
    private let batchSize = 25
    private var isFlushing = false

    private init() {
        UserDefaults.standard.register(defaults: [Keys.analyticsEnabled: true])
    }

    var analyticsEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.analyticsEnabled) as? Bool ?? true
    }

    func setAnalyticsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.analyticsEnabled)
        if !enabled {
            saveQueue([])
        }
    }

    func track(_ name: TelemetryEventName, properties: [String: TelemetryValue] = [:]) async {
        guard analyticsEnabled else { return }

        let sanitizedProperties = sanitize(properties: properties, for: name)
        let event = TelemetryEvent(
            id: UUID(),
            event: name.rawValue,
            properties: sanitizedProperties,
            context: makeContext()
        )

        var queue = loadQueue()
        queue.append(event)
        if queue.count > maxQueuedEvents {
            queue = Array(queue.suffix(maxQueuedEvents))
        }
        saveQueue(queue)

        await flush()
    }

    func flush() async {
        guard analyticsEnabled, !isFlushing, let endpoint = telemetryEndpointURL else { return }

        var queue = loadQueue()
        guard !queue.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(queue.prefix(batchSize))
        let payload = TelemetryBatch(events: batch)

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = telemetryAPIKey {
                request.setValue(apiKey, forHTTPHeaderField: "x-assetfox-telemetry-key")
            }
            request.httpBody = try JSONEncoder().encode(payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard analyticsEnabled else { return }

            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                queue.removeFirst(min(batch.count, queue.count))
                saveQueue(queue)
            }
        } catch {
            logger.debug("Telemetry delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var telemetryEndpointURL: URL? {
        if let override = UserDefaults.standard.string(forKey: Keys.endpointURL),
           let url = URL(string: override),
           isHTTPSURL(url) {
            return url
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "AssetFoxTelemetryEndpointURL") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: value),
           isHTTPSURL(url) {
            return url
        }

        return nil
    }

    private var telemetryAPIKey: String? {
        if let override = UserDefaults.standard.string(forKey: "assetfox.telemetry.apiKey"),
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "AssetFoxTelemetryAPIKey") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return nil
    }

    private func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.isEmpty == false
    }

    private func sanitize(properties: [String: TelemetryValue], for event: TelemetryEventName) -> [String: TelemetryValue] {
        let allowedKeys: Set<String>
        switch event {
        case .appLaunched, .duplicateScanStarted, .collectMediaStarted:
            allowedKeys = []
        case .sectionOpened:
            allowedKeys = ["section"]
        case .qcFilesAdded:
            allowedKeys = ["count"]
        case .qcAnalysisStarted:
            allowedKeys = ["file_count"]
        case .qcAnalysisCompleted:
            allowedKeys = ["duration_ms", "findings_count"]
        case .qcAnalysisFailed:
            allowedKeys = ["reason_code"]
        case .duplicateScanCompleted:
            allowedKeys = ["groups_count", "files_count"]
        case .collectMediaCompleted:
            allowedKeys = ["copied_count", "missing_count"]
        case .ingestStarted:
            allowedKeys = ["file_count", "verification_enabled"]
        case .ingestCompleted:
            allowedKeys = ["file_count", "verification_enabled", "failed_count"]
        case .mediaInfoFilesAdded:
            allowedKeys = ["count"]
        case .mediaInfoExported:
            allowedKeys = ["format"]
        }

        return properties.filter { allowedKeys.contains($0.key) }
    }

    private func makeContext() -> TelemetryContext {
        TelemetryContext(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processorArch: processorArch,
            anonymousInstallationID: installationID(),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private var processorArch: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private func installationID() -> String {
        if let existing = UserDefaults.standard.string(forKey: Keys.installationID), !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: Keys.installationID)
        return newID
    }

    private func loadQueue() -> [TelemetryEvent] {
        guard let data = UserDefaults.standard.data(forKey: Keys.queue),
              let events = try? JSONDecoder().decode([TelemetryEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func saveQueue(_ events: [TelemetryEvent]) {
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.queue)
            return
        }

        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Keys.queue)
        }
    }
}

private struct TelemetryBatch: Codable {
    let events: [TelemetryEvent]
}
