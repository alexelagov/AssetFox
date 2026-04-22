import SwiftUI

private let assetFoxMinimumWindowSize = CGSize(width: 980, height: 680)
private let assetFoxNavigationSidebarWidth: CGFloat = 300

@main
struct AssetFoxApp: App {
    var body: some Scene {
        WindowGroup {
            AssetFoxRootView()
                .frame(
                    minWidth: assetFoxMinimumWindowSize.width,
                    minHeight: assetFoxMinimumWindowSize.height
                )
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultWindowPlacement { content, context in
            let visibleRect = context.defaultDisplay.visibleRect

            return WindowPlacement(
                size: defaultAssetFoxWindowSize(visibleRect: visibleRect)
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            AssetFoxNavigationCommands()
        }
    }
}

private func defaultAssetFoxWindowSize(visibleRect: CGRect) -> CGSize {
    let twoColumnWorkspaceWidth = AssetFoxDesign.pageMaxWidth
        + AssetFoxDesign.pageHorizontalPadding * 2
        + assetFoxNavigationSidebarWidth

    let preferredSize = CGSize(
        width: twoColumnWorkspaceWidth,
        height: visibleRect.height * 0.78
    )

    return CGSize(
        width: min(max(preferredSize.width, assetFoxMinimumWindowSize.width), visibleRect.width * 0.82),
        height: min(max(preferredSize.height, assetFoxMinimumWindowSize.height), visibleRect.height * 0.82)
    )
}

private struct AssetFoxNavigationCommands: Commands {
    @FocusedBinding(\.assetFoxSectionSelection) private var selectedSection

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(AssetFoxSection.allCases) { section in
                Button(section.title) {
                    selectedSection = section
                }
                .keyboardShortcut(section.keyboardShortcut, modifiers: [.command])
            }
        }
    }
}
