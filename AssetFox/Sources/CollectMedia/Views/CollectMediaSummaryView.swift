import SwiftUI

struct CollectMediaSummaryView: View {
    let result: CollectResult
    let onOpenDestination: () -> Void
    let onRevealReport: () -> Void
    let onRevealMissing: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Collect Summary")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Found", value: "\(result.counts.found)")
                    summaryRow("Copied", value: "\(result.counts.copied)")
                    summaryRow("Missing", value: "\(result.counts.missing)")
                    summaryRow("Skipped", value: "\(result.counts.skipped)")
                    summaryRow("Status", value: result.status == .completed ? "Completed" : "Stopped by user")
                    summaryRow("Destination", value: result.destinationURL.path)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button("Open Destination in Finder", action: onOpenDestination)
                Button("Reveal report.csv", action: onRevealReport)
                    .disabled(!FileManager.default.fileExists(atPath: result.reportCSVURL.path))
                Button("Reveal missing.txt", action: onRevealMissing)
                    .disabled(result.missingTextURL == nil)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
