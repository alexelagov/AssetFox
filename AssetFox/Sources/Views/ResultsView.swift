import SwiftUI

struct ResultsView: View {
    @Bindable var vm: AppViewModel
    @State private var pendingDeleteAction: PendingDeleteAction?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(vm: vm)
                .frame(width: 300)

            Divider()

            if let id = vm.selectedGroupID,
               let group = vm.groups.first(where: { $0.id == id }) {
                GroupDetailView(group: group, vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a Duplicate Set",
                    systemImage: "doc.on.doc",
                    description: Text("Choose a set from the sidebar to review the files inside it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    guard let group = currentGroup else { return }
                    pendingDeleteAction = .group(group)
                } label: {
                    Label("Delete Duplicates", systemImage: "trash")
                }
                .tint(.orange)
                .disabled(currentGroup?.selectedIndexes.isEmpty ?? true)

                Button {
                    vm.reset()
                } label: {
                    Label("New Scan", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .alert(
            pendingDeleteAction?.title ?? "Delete Duplicates",
            isPresented: Binding(
                get: { pendingDeleteAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteAction = nil
                    }
                }
            ),
            presenting: pendingDeleteAction
        ) { action in
            Button(action.confirmButtonTitle, role: .destructive) {
                performDelete(action)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    private func performDelete(_ action: PendingDeleteAction) {
        switch action {
        case .group(let group):
            vm.trashGroup(group)
        case .all:
            vm.trashAll()
        }
        pendingDeleteAction = nil
    }

    private var currentGroup: DuplicateGroup? {
        guard let id = vm.selectedGroupID else { return nil }
        return vm.groups.first(where: { $0.id == id })
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Duplicate Finder")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

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
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
        .background(.bar)
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
                            isSelected: group.selectedIndexes.contains(index),
                            selectedCount: group.selectedIndexes.count,
                            totalCount: group.files.count,
                            isOldest: index == 0
                        ) {
                            vm.toggleSelection(groupID: group.id, index: index)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Text(selectionSummary(for: group))
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
                .disabled(group.selectedIndexes.isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }

    private func selectionSummary(for group: DuplicateGroup) -> String {
        let selectedCount = group.selectedIndexes.count
        let keptCount = group.files.count - selectedCount

        if selectedCount == 0 {
            return "No files are selected. Pick one or more duplicates to move to quarantine."
        }

        return "\(selectedCount) file\(selectedCount == 1 ? "" : "s") selected for action. \(keptCount) file\(keptCount == 1 ? "" : "s") will stay in place."
    }
}

// MARK: - File Row

struct FileRowView: View {
    let file: ScannedFile
    let isSelected: Bool
    let selectedCount: Int
    let totalCount: Int
    let isOldest: Bool
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onKeep()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(selectionHelpText)

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
                    if isSelected {
                        Text("selected")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    } else {
                        Text("stays")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(Color.secondary)
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
                .fill(isSelected ? Color.green.opacity(0.06) : Color(.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.green.opacity(0.25) : Color.clear, lineWidth: 1)
                )
        )
    }

    private var selectionHelpText: String {
        if isSelected {
            return "Deselect this file so it stays in place"
        }

        if selectedCount >= totalCount - 1 {
            return "At least one file in the set must stay unselected"
        }

        return "Select this file for delete or quarantine"
    }
}

private enum PendingDeleteAction {
    case group(DuplicateGroup)
    case all

    var title: String {
        switch self {
        case .group:
            return "Delete Duplicate Files?"
        case .all:
            return "Delete All Duplicates?"
        }
    }

    var message: String {
        switch self {
        case .group(let group):
            let selectedCount = group.selectedIndexes.count
            let keptCount = group.files.count - selectedCount
            return "This will move \(selectedCount) selected file\(selectedCount == 1 ? "" : "s") from the current duplicate set to the Mac Trash. \(keptCount) file\(keptCount == 1 ? "" : "s") will stay in place."
        case .all:
            return "This will move every duplicate file from every set to the Mac Trash. One keep file per set will stay in place."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .group:
            return "Delete"
        case .all:
            return "Delete All"
        }
    }
}
