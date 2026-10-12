import SwiftUI
import StudioKit

@main
struct CardsiteApp: App {
    @State private var model = AppModel()

    init() {
        StudioFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .studioViewport()
                .tint(.studioAccentLine)
                .task { await model.restore() }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            CardsiteCommands(model: model)
        }
    }
}

/// Menu-bar commands on Mac; keyboard shortcuts on iPad with a hardware
/// keyboard (hold ⌘ to see them). Built from the registry, so a new
/// destination or create action appears here without an edit.
struct CardsiteCommands: Commands {
    let model: AppModel
    /// The focused window's navigation, nil when no signed-in window has focus.
    @FocusedValue(\.shellRouter) private var router

    var body: some Commands {
        CommandGroup(after: .newItem) {
            ForEach(CreateAction.allCases) { action in
                Button(action.title) { model.composer = action.composer }
                    .keyboardShortcut(action.shortcut)
                    .disabled(model.user == nil)
            }
        }

        CommandMenu("Go") {
            Button("Search…") { router?.togglePalette() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(router == nil)

            Divider()

            ForEach(AppDestination.allCases) { destination in
                if let key = destination.shortcut {
                    Button(destination.title) { router?.open(destination) }
                        .keyboardShortcut(key, modifiers: .command)
                        .disabled(router == nil)
                }
            }
        }
    }
}
