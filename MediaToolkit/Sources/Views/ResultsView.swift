import SwiftUI

struct ResultsView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let id = vm.selectedGroupID,
               let group = vm.groups.first(where: { $0.id == id }) {
                GroupDetailView(group: group, vm: vm)
            } else {
                ContentUnavailableView(
                    "Select a Duplicate Set",
                    systemImage: "doc.on.doc",
                    description: Text("Choose a set from the sidebar to review the files inside it.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    vm.quarantineAll()
                } label: {
                    Label("Move All to Quarantine", systemImage: "trash")
                }
                .tint(.orange)

                Button {
                    vm.reset()
                } label: {
                    Label("New Scan", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        List(vm.groups, selection: $vm.selectedGroupID) { group in
            GroupRowView(group: group)
                .tag(group.id)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vm.groups.count) duplicate sets")
                            .font(.caption.weight(.medium))
                        Text("Space you can recover: \(vm.totalWasted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}

struct GroupRowView: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.files.first?.name ?? "")
                .font(.system(.body, design: .default))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(group.files.count) files")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(group.sizeFormatted)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("−\(group.wastedFormatted)")
                    .foregroundStyle(.orange)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Group Detail

struct GroupDetailView: View {
    let group: DuplicateGroup
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.files.first?.name ?? "")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(group.files.count) files", systemImage: "doc.on.doc")
                    Label(group.sizeFormatted + " each", systemImage: "scalemass")
                    Label("Recover \(group.wastedFormatted)", systemImage: "arrow.down.circle")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        FileRowView(
                            file: file,
                            isKept: index == group.keepIndex,
                            isOldest: index == 0
                        ) {
                            vm.setKeep(groupID: group.id, index: index)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Text("File \(group.keepIndex + 1) will be kept. The rest will be moved to quarantine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip Set") {
                    if let idx = vm.groups.firstIndex(where: { $0.id == group.id }),
                       idx + 1 < vm.groups.count {
                        vm.selectedGroupID = vm.groups[idx + 1].id
                    }
                }
                .buttonStyle(.bordered)

                Button("Quarantine") {
                    vm.quarantineGroup(group)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(.bar)
        }
    }
}

// MARK: - File Row

struct FileRowView: View {
    let file: ScannedFile
    let isKept: Bool
    let isOldest: Bool
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onKeep()
            } label: {
                Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isKept ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    if isOldest {
                        Text("oldest")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(Color.blue)
                            .clipShape(Capsule())
                    }
                    if isKept {
                        Text("kept")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }
                }
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(file.sizeFormatted)
                    .font(.caption.weight(.medium))
                Text(file.modifiedFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isKept ? Color.green.opacity(0.06) : Color(.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isKept ? Color.green.opacity(0.25) : Color.clear, lineWidth: 1)
                )
        )
    }
}
