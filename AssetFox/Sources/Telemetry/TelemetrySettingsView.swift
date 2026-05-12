import SwiftUI

struct AssetFoxTelemetrySettingsView: View {
    @AppStorage("assetfox.telemetry.analyticsEnabled") private var analyticsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Share anonymous usage analytics", isOn: $analyticsEnabled)
                .toggleStyle(.switch)
                .onChange(of: analyticsEnabled) { _, newValue in
                    Task {
                        await TelemetryService.shared.setAnalyticsEnabled(newValue)
                    }
                }

            Text("AssetFox sends anonymous usage and diagnostic events to help improve the app. No file names, file paths, media content, project names, raw ffmpeg output, or user-entered text are collected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
