import SwiftUI
import StudioKit
import CardsiteKit

/// Full-area states for a list that has nothing to show yet.
struct ListStateView<Item, Content: View>: View {
    let state: Loadable<[Item]>
    let empty: EmptyContent
    let retry: @MainActor @Sendable () async -> Void
    @ViewBuilder let content: ([Item]) -> Content

    struct EmptyContent {
        let systemImage: String
        let title: String
        let message: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading")
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let items) where items.isEmpty:
            ScrollView {
                StudioEmptyState(systemImage: empty.systemImage, title: empty.title, message: empty.message) {
                    if let actionTitle = empty.actionTitle, let action = empty.action {
                        StudioButton(actionTitle, systemImage: "plus", variant: .primary, action: action)
                    }
                }
                .padding(StudioSpace.s6)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .refreshable { [retry] in await retry() }
        case .loaded(let items):
            content(items)
        }
    }
}

struct ErrorStateView: View {
    let error: APIError
    let retry: @MainActor @Sendable () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            StudioEmptyState(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: error == .offline ? String(localized: "You're offline") : String(localized: "Couldn't load this"),
                message: error.localizedDescription
            ) {
                if error.isRetryable || error == .offline {
                    StudioButton("Try Again", systemImage: "arrow.clockwise", variant: .outline, isLoading: isRetrying) {
                        Task {
                            isRetrying = true
                            await retry()
                            isRetrying = false
                        }
                    }
                }
            }
            .padding(StudioSpace.s6)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .refreshable { [retry] in await retry() }
    }
}

/// A load failure inside a page that keeps the rest of its content, such
/// as a dashboard section. `ErrorStateView` is the full-area version.
struct InlineErrorState: View {
    let error: APIError
    let retry: @MainActor @Sendable () async -> Void
    @State private var isRetrying = false

    var body: some View {
        StudioEmptyState(
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            title: error == .offline ? String(localized: "You're offline") : String(localized: "Couldn't load this"),
            message: error.localizedDescription
        ) {
            if error.isRetryable || error == .offline {
                StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline, isLoading: isRetrying) {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                }
            }
        }
    }
}

/// A one-line banner above a list whose refresh failed while it still has
/// data to show.
struct RefreshErrorBanner: View {
    let error: APIError
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s2) {
            StudioBanner(lead: String(localized: "Not up to date."), message: error.localizedDescription, tone: .warning)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .padding(StudioSpace.s2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }
}

/// An inline error under a form.
struct FormErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
                .transition(.opacity)
        }
    }
}

/// The Cardsite icon mark, from the Brand Kit SVG
/// (internal/@csxbase/brand-kit/assets/logos/cardsite-icon-mark.svg),
/// kept as vector data in the asset catalog. The Brand Kit forbids redrawing it.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
