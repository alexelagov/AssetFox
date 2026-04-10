import SwiftUI

@main
struct AssetFoxApp: App {
    var body: some Scene {
        WindowGroup {
            AssetFoxRootView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
