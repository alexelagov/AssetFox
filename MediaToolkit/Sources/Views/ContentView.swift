import SwiftUI

struct ContentView: View {
    @State private var vm = AppViewModel()

    var body: some View {
        Group {
            switch vm.phase {
            case .idle:
                DropZoneView(vm: vm)
            case .scanning, .hashing:
                ScanProgressView(vm: vm)
            case .done:
                if vm.groups.isEmpty {
                    NoDuplicatesView(vm: vm)
                } else {
                    ResultsView(vm: vm)
                }
            case .error(let msg):
                ErrorView(message: msg, vm: vm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: vm.phase)
    }
}
