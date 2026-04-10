import SwiftUI

struct ScanProgressView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)

            VStack(spacing: 10) {
                switch vm.phase {
                case .scanning(_, let current):
                    Text("Scanning folder...")
                        .font(.title3.weight(.medium))
                    Text(current.isEmpty ? " " : current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)

                case .hashing(let progress, let current):
                    Text("Analyzing duplicates...")
                        .font(.title3.weight(.medium))
                    ProgressView(value: progress)
                        .frame(width: 300)
                    Text(current.isEmpty ? " " : current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)
                default:
                    EmptyView()
                }
            }

            if let root = vm.rootURL {
                Text(root.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 500)
            }

            Spacer()
        }
        .padding()
    }
}
