import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Bindable var vm: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Duplicate Finder")
                        .font(.largeTitle.weight(.semibold))
                    Text("Scan a folder to find duplicate media and reclaim disk space.")
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                        .frame(width: 380, height: 160)

                    VStack(spacing: 12) {
                        Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        Text(isTargeted ? "Drop to start scanning" : "Drop a folder here")
                            .font(.headline)
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    }
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
                    Button {
                        pickFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                            .frame(width: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if vm.rootURL != nil {
                        Button("Scan Again") { vm.startScan() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                }
            }

            Spacer()

            // Footer hint
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("Supports MXF, MOV, MP4, JPEG, PNG, PDF, and other common media formats.")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 20)
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
