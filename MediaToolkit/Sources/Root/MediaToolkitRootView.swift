import SwiftUI

struct MediaToolkitRootView: View {
    @State private var selection: TopLevelTab = .duplicateFinder

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tabItem {
                    Label("DuplicateFinder", systemImage: "doc.on.doc")
                }
                .tag(TopLevelTab.duplicateFinder)

            CollectMediaView()
                .tabItem {
                    Label("Collect Media", systemImage: "shippingbox")
                }
                .tag(TopLevelTab.collectMedia)
        }
    }
}

private enum TopLevelTab: Hashable {
    case duplicateFinder
    case collectMedia
}
