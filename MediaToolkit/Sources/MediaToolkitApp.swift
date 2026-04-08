import SwiftUI

@main
struct MediaToolkitApp: App {
    var body: some Scene {
        WindowGroup {
            MediaToolkitRootView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
