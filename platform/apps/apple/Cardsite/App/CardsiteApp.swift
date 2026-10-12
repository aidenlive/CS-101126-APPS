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

/// Menu-bar commands on Mac; keyboard shortcuts on iPad with a hardware keyboard.
struct CardsiteCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Short Link") { model.composer = .link }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.user == nil)
            Button("New QR Code") { model.composer = .qrCode }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.user == nil)
        }
    }
}
