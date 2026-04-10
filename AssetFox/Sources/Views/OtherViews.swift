import SwiftUI

struct NoDuplicatesView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("No duplicates found")
                    .font(.title2.weight(.semibold))
                Text("This folder looks clean.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let root = vm.rootURL {
                    Text(root.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Scan Another Folder") { vm.reset() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

struct ErrorView: View {
    let message: String
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            Button("Try Again") { vm.reset() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}
