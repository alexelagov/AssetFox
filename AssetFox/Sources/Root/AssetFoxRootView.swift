import SwiftUI

struct AssetFoxRootView: View {
    @State private var selection: TopLevelTab = .duplicateFinder

    var body: some View {
        TabView(selection: $selection) {
            ContentView()
                .tabItem {
                    Label("Duplicate Finder", systemImage: "doc.on.doc")
                }
                .tag(TopLevelTab.duplicateFinder)

            CollectMediaView()
                .tabItem {
                    Label("Collect Media", systemImage: "shippingbox")
                }
                .tag(TopLevelTab.collectMedia)

            IngestView()
                .tabItem {
                    Label("Ingest", systemImage: "square.and.arrow.down.on.square")
                }
                .tag(TopLevelTab.ingest)

            MediaInfoView()
                .tabItem {
                    Label("Media Info", systemImage: "info.square")
                }
                .tag(TopLevelTab.mediaInfo)
        }
    }
}

private enum TopLevelTab: Hashable {
    case duplicateFinder
    case collectMedia
    case ingest
    case mediaInfo
}
