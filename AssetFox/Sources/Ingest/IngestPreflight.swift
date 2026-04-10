import Foundation

enum IngestPreflightSeverity {
    case warning
    case error
}

struct IngestPreflightIssue: Identifiable {
    let id = UUID()
    let severity: IngestPreflightSeverity
    let message: String
}
