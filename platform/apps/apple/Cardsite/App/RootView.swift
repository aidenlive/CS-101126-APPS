import SwiftUI
import StudioKit
import CardsiteKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                AuthFlowView()
                    .transition(.opacity)
            case .signedIn:
                MainView(client: model.client)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.phase == .signedOut)
        .background(Color.studioBg.ignoresSafeArea())
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: StudioSpace.s4) {
            BrandMark(size: 56)
            ProgressView()
                .accessibilityLabel("Loading")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MainTab: String, Hashable {
    case links, qrCodes, pages, account
}

/// The signed-in app. A native tab view: a tab bar on iPhone, a tab bar that
/// becomes a sidebar on iPad, and a sidebar on Mac. Bars get the system's
/// Liquid Glass material on OS 26+; content surfaces stay opaque Studio
/// surfaces, as the HIG asks.
///
/// The list models live here, not in the tabs, so an item created from a
/// menu command or keyboard shortcut appears in its list straight away and
/// switching tabs does not refetch.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("main.tab") private var tab: MainTab = .links
    @State private var links: LinksModel
    @State private var qrCodes: QRCodesModel
    @State private var pages: PagesModel

    init(client: APIClient) {
        _links = State(initialValue: LinksModel(client: client))
        _qrCodes = State(initialValue: QRCodesModel(client: client))
        _pages = State(initialValue: PagesModel(client: client))
    }

    var body: some View {
        @Bindable var bindable = model
        TabView(selection: $tab) {
            Tab("Links", systemImage: "link", value: MainTab.links) {
                LinksScreen()
            }
            Tab("QR Codes", systemImage: "qrcode", value: MainTab.qrCodes) {
                QRCodesScreen()
            }
            Tab("Pages", systemImage: "person.crop.square", value: MainTab.pages) {
                PagesScreen()
            }
            Tab("Account", systemImage: "person.circle", value: MainTab.account) {
                AccountScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(links)
        .environment(qrCodes)
        .environment(pages)
        .sheet(item: $bindable.composer) { composer in
            switch composer {
            case .link:
                LinkEditorView { _ in tab = .links }
                    .environment(links)
            case .qrCode:
                QRCodeEditorView { _ in tab = .qrCodes }
                    .environment(qrCodes)
            }
        }
        .task {
            // After an offline launch the profile is a placeholder.
            if model.needsProfile { await model.refreshUser() }
        }
        .onAppear {
            links.onError = model.handle
            qrCodes.onError = model.handle
            pages.onError = model.handle
        }
    }
}
