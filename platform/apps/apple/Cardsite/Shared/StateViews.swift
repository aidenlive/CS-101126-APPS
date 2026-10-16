import SwiftUI
import StudioKit
import CardsiteKit

/// Full-area states for a list that has nothing to show yet: a skeleton
/// of the list while the first page loads, the empty state with its
/// primary action, and the error with Try Again.
///
/// A full-width destination passes its `head`: the page head then stays
/// in every state (PARITY-PLAN §6), with the skeleton, the empty state or
/// the error below it, laid out exactly as the loaded list lays it out.
struct ListStateView<Item, Content: View>: View {
    let state: Loadable<[Item]>
    let empty: EmptyContent
    var head: ListPageHeadContent? = nil
    var skeleton: ListSkeleton = .resourceRows
    let retry: @MainActor @Sendable () async -> Void
    @ViewBuilder let content: ([Item]) -> Content

    struct EmptyContent {
        let systemImage: String
        let title: String
        let message: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    init(state: Loadable<[Item]>, empty: EmptyContent, head: ListPageHeadContent? = nil,
         skeleton: ListSkeleton = .resourceRows,
         retry: @escaping @MainActor @Sendable () async -> Void,
         @ViewBuilder content: @escaping ([Item]) -> Content) {
        self.state = state
        self.empty = empty
        self.head = head
        self.skeleton = skeleton
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            ListSkeletonView(style: skeleton, head: head)
        case .failed(let error):
            ErrorStateView(error: error, head: head, retry: retry)
        case .loaded(let items) where items.isEmpty:
            if let head {
                // The same List as the loaded state, so the head doesn't move
                // when the first item arrives.
                List {
                    ListPageHead(head)
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .studioClearRow()
                    }
                }
                .studioList()
                .refreshable { [retry] in await retry() }
            } else {
                ScrollView {
                    emptyState
                        .padding(StudioSpace.s6)
                        .readableWidth(.sheet)
                }
                .background(Color.studioBg)
                .refreshable { [retry] in await retry() }
            }
        case .loaded(let items):
            content(items)
        }
    }

    private var emptyState: some View {
        StudioEmptyState(systemImage: empty.systemImage, title: empty.title, message: empty.message) {
            if let actionTitle = empty.actionTitle, let action = empty.action {
                StudioButton(actionTitle, systemImage: "plus", variant: .primary, action: action)
            }
        }
    }
}

/// The shape of a list's loading skeleton.
enum ListSkeleton {
    /// Glyph tile, title, address and clicks: resource lists.
    case resourceRows
    /// Title over two lines of text, no tile: Inbox, logs, records.
    case textRows
}

/// Six placeholder rows in the real row anatomy, redacted, so nothing
/// jumps when the first page lands. VoiceOver hears one "Loading".
///
/// With a `head`, the page head is drawn for real above the placeholder
/// rows; VoiceOver reads the head, then one "Loading".
struct ListSkeletonView: View {
    var style: ListSkeleton = .resourceRows
    var head: ListPageHeadContent? = nil

    var body: some View {
        if let head {
            List {
                ListPageHead(head)
                Section {
                    ForEach(0..<6, id: \.self) { index in
                        row(index)
                            .redacted(reason: .placeholder)
                            .loadingAccessibility(true)
                            .accessibilityHidden(index > 0)
                    }
                }
                .studioRowBackground()
            }
            .studioList()
            .disabled(true)
        } else {
            List {
                ForEach(0..<6, id: \.self) { index in
                    row(index)
                        .studioRowBackground()
                }
            }
            .studioList()
            .redacted(reason: .placeholder)
            .disabled(true)
            .loadingAccessibility(true)
        }
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        switch style {
        case .resourceRows:
            CardsiteResourceRow(
                systemImage: "link",
                title: Text(verbatim: index.isMultiple(of: 2) ? "card.site/placeholder" : "card.site/a-longer-address"),
                subtitle: Text(verbatim: "example.com/destination"),
                clicks: 1_000
            )
        case .textRows:
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: index.isMultiple(of: 2) ? "A placeholder title" : "A longer placeholder title")
                    .studioText(.ui)
                Text(verbatim: "Two lines of placeholder text stand in for the details while they load.")
                    .studioText(.uiSm)
                    .lineLimit(2)
            }
            .padding(.vertical, StudioSpace.s1)
        }
    }
}

extension View {
    /// While `isLoading`, one "Loading" element instead of placeholder text.
    @ViewBuilder
    func loadingAccessibility(_ isLoading: Bool) -> some View {
        if isLoading {
            accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading"))
        } else {
            self
        }
    }
}

/// A full-area load failure, with Try Again when trying again can help.
///
/// With a `head` (a full-width destination), the page head stays above it.
struct ErrorStateView: View {
    let error: APIError
    var head: ListPageHeadContent? = nil
    let retry: @MainActor @Sendable () async -> Void
    @State private var isRetrying = false

    init(error: APIError, head: ListPageHeadContent? = nil,
         retry: @escaping @MainActor @Sendable () async -> Void) {
        self.error = error
        self.head = head
        self.retry = retry
    }

    var body: some View {
        if let head {
            List {
                ListPageHead(head)
                Section {
                    state
                        .listRowInsets(EdgeInsets())
                        .studioClearRow()
                }
            }
            .studioList()
            .refreshable { [retry] in await retry() }
        } else {
            ScrollView {
                state
                    .padding(StudioSpace.s6)
                    .readableWidth(.sheet)
            }
            .background(Color.studioBg)
            .refreshable { [retry] in await retry() }
        }
    }

    private var state: some View {
        StudioEmptyState(
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            title: error == .offline ? String(localized: "You’re offline") : String(localized: "Couldn’t load this"),
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

/// A load failure inside a page that keeps the rest of its content, such
/// as a dashboard section. Compact: its container (a `StudioCard`) draws
/// the frame. `ErrorStateView` is the full-area version.
struct InlineErrorState: View {
    let error: APIError
    let retry: @MainActor @Sendable () async -> Void
    @State private var isRetrying = false

    var body: some View {
        StudioEmptyState(
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            title: error == .offline ? String(localized: "You’re offline") : String(localized: "Couldn’t load this"),
            message: error.localizedDescription,
            compact: true
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

/// An empty split-view column ("Select a link"): the Studio empty state on
/// the page background, so an empty detail pane looks like an empty list.
struct SplitPlaceholder: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        StudioEmptyState(systemImage: systemImage, title: title, message: message, compact: true) {
            EmptyView()
        }
        .padding(StudioSpace.s6)
        .readableWidth(.sheet)
        .frame(maxHeight: .infinity)
        .background(Color.studioBg)
    }
}

/// A load failure as a Form row: the message, and Try Again trailing.
/// Every inline load failure inside a Form uses it.
struct FormRetryRow: View {
    let message: String
    var systemImage = "exclamationmark.triangle"
    let retry: @MainActor @Sendable () async -> Void
    @State private var isRetrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
            Label {
                Text(message)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.studioText3)
            }
            Spacer(minLength: StudioSpace.s2)
            if isRetrying {
                ProgressView()
                    .accessibilityLabel(Text("Trying again"))
            } else {
                Button(String(localized: "Try Again")) {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                }
                .fixedSize()
            }
        }
    }
}

/// A banner above a list whose refresh failed while it still has data to
/// show. StudioKit's dismissible banner.
struct RefreshErrorBanner: View {
    let error: APIError
    let dismiss: () -> Void

    var body: some View {
        StudioBanner(lead: String(localized: "Not up to date."), message: error.localizedDescription,
                     tone: .warning, onDismiss: dismiss)
    }
}

extension EnvironmentValues {
    /// The shell's toast centre (`MainView`), for success feedback from any
    /// screen. Nil in previews and outside the signed-in shell.
    @Entry var toasts: StudioToastCenter? = nil
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
