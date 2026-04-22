import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Bindable var vm: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AssetFoxPageHeader(
                    title: "Duplicate Finder",
                    systemImage: "doc.on.doc",
                    subtitle: "Scan a folder to find duplicate media and reclaim disk space."
                )

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOURCE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Scan folder")
                            .font(.title3.weight(.semibold))
                        Text("Drop a folder into the target or choose one from disk.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: AssetFoxDesign.panelRadius, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: AssetFoxDesign.panelRadius, style: .continuous)
                                    .strokeBorder(
                                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                                    )
                            )
                            .frame(minHeight: 190)

                        VStack(spacing: 12) {
                            Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                            Text(isTargeted ? "Drop to start scanning" : "Drop a folder here")
                                .font(.headline)
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
                            Text("Supports MXF, MOV, MP4, JPEG, PNG, PDF, and other common media formats.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(24)
                    }
                    .dropDestination(for: URL.self) { items, _ in
                        guard let url = items.first else { return false }
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                        guard isDir.boolValue else { return false }
                        vm.rootURL = url
                        vm.startScan()
                        return true
                    } isTargeted: { isTargeted = $0 }

                    HStack(spacing: 12) {
                        Button("Choose Folder") {
                            pickFolder()
                        }
                        .buttonStyle(.borderedProminent)

                        if vm.rootURL != nil {
                            Button("Scan Again") { vm.startScan() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(AssetFoxDesign.panelPadding)
                .background(AssetFoxPanelBackground())
            }
            .frame(maxWidth: AssetFoxDesign.pageMaxWidth, alignment: .leading)
            .padding(.horizontal, AssetFoxDesign.pageHorizontalPadding)
            .padding(.vertical, AssetFoxDesign.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            vm.rootURL = url
            vm.startScan()
        }
    }
}
