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
                // Keyed on the workspace scope: switching workspaces builds
                // a fresh shell, so no screen keeps the previous
                // workspace's rows, selection or drafts.
                MainView(client: model.client)
                    .id(model.workspaceScope)
                    .transition(.opacity)
            }
        }
        .animation(StudioAnimation.base, value: model.phase == .signedOut)
        .animation(StudioAnimation.base, value: model.workspaceScope)
        .background(Color.studioBg.ignoresSafeArea())
        // Widgets, the share extension and Siri open `cardsite://` links.
        // Held on the model so one that arrives at launch, or before
        // sign-in (the share extension's "Open Cardsite"), is routed once
        // the signed-in shell is up.
        .onOpenURL { url in
            if let link = CardsiteDeepLink(url: url) {
                model.pendingDeepLink = link
            }
        }
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
