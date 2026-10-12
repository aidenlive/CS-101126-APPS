import SwiftUI
import StudioKit
import CardsiteKit

/// The root for the registry: its own navigation stack. Uses the shell's
/// ``InboxModel`` when one is in the environment, so the badge and the list
/// agree; otherwise it keeps its own.
struct InboxScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(InboxModel.self) private var shared: InboxModel?

    var body: some View {
        NavigationStack {
            if let shared {
                InboxView(model: shared)
            } else {
                OwnedInbox(client: app.client, onError: { [app] in app.handle($0) })
            }
        }
    }
}

private struct OwnedInbox: View {
    @State private var model: InboxModel

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        let model = InboxModel(client: client)
        model.onError = onError
        _model = State(initialValue: model)
    }

    var body: some View { InboxView(model: model) }
}

/// All / Unread, mark read, mark all read. Tapping a notification with an
/// address opens it in the browser and marks it read.
struct InboxView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let model: InboxModel
    @State private var actionError: String?

    var body: some View {
        @Bindable var model = model
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "tray",
                title: String(localized: "No inbox notifications yet."),
                message: String(localized: "Announcements and updates about your account and workspaces arrive here.")
            ),
            retry: { [model] in await model.refresh() }
        ) { _ in
            list
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $model.filter) {
                    Text("All").tag(InboxModel.Filter.all)
                    Text(model.unreadCount > 0 ? "Unread (\(model.unreadCount))" : "Unread")
                        .tag(InboxModel.Filter.unread)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                if model.isMarkingAll {
                    ProgressView()
                } else {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        Label("Mark all as read", systemImage: "envelope.open")
                    }
                    .disabled(model.unreadCount == 0 && !model.list.items.contains { !$0.isRead })
                }
            }
        }
        .task { [model] in
            await model.list.loadIfNeeded()
            await model.refreshUnreadCount()
        }
        .alert("Couldn't update the inbox",
               isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var list: some View {
        List {
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .listRowSeparator(.hidden)
            }
            if model.visibleItems.isEmpty {
                ContentUnavailableView(
                    "You're all caught up",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing unread.")
                )
                .listRowSeparator(.hidden)
            }
            ForEach(model.visibleItems) { item in
                let destination = item.destination(relativeTo: app.configuration.webURL)
                Button {
                    Task { await open(item, at: destination) }
                } label: {
                    InboxRow(item: item, opensLink: destination != nil)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: item, destination: destination) }
                .swipeActions(edge: .leading) {
                    if !item.isRead {
                        Button {
                            Task { await markRead(item) }
                        } label: {
                            Label("Mark as read", systemImage: "envelope.open")
                        }
                        .tint(.studioInfo)
                    }
                }
            }
            if model.list.hasMore, model.filter == .all {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
            }
        }
        .refreshable { await model.refresh() }
        .animation(StudioAnimation.base, value: model.filter)
    }

    @ViewBuilder
    private func menu(for item: InboxNotification, destination: URL?) -> some View {
        if !item.isRead {
            Button {
                Task { await markRead(item) }
            } label: {
                Label("Mark as read", systemImage: "envelope.open")
            }
        }
        if let destination {
            Button {
                Task { await open(item, at: destination) }
            } label: {
                Label("View details", systemImage: "safari")
            }
            Button {
                Pasteboard.copy(destination.absoluteString)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
        }
    }

    private func open(_ item: InboxNotification, at destination: URL?) async {
        if let destination { openURL(destination) }
        await markRead(item)
    }

    private func markRead(_ item: InboxNotification) async {
        guard !item.isRead else { return }
        do {
            try await model.markRead(item)
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
    }

    private func markAllRead() async {
        do {
            try await model.markAllRead()
            Haptics.success()
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
    }
}

/// Unread dot, title, description and time; a trailing arrow when tapping
/// opens a page.
struct InboxRow: View {
    let item: InboxNotification
    let opensLink: Bool

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Circle()
                .fill(item.isRead ? Color.clear : Color.studioAccent)
                .frame(width: StudioSpace.s2, height: StudioSpace.s2)
                .padding(.top, StudioSpace.s2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: item.title)
                    .studioText(.ui)
                    .fontWeight(item.isRead ? .regular : .semibold)
                    .foregroundStyle(Color.studioText)
                if let description = item.description, !description.isEmpty {
                    Text(verbatim: description)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .lineLimit(3)
                }
                if let date = item.createdAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            Spacer(minLength: StudioSpace.s2)
            if opensLink {
                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(Color.studioText3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? Text("") : Text("Unread"))
        .accessibilityHint(opensLink ? Text("Opens in your browser") : Text(""))
    }
}

#if DEBUG
#Preview("Inbox") {
    let model = InboxModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed([
        InboxNotification(id: 4, title: "Welcome to Cardsite", description: "Your workspace is ready.",
                          url: "/dashboard", isRead: false, createdAt: .now.addingTimeInterval(-600)),
        InboxNotification(id: 3, title: "Scheduled maintenance",
                          description: "Cardsite will be read-only for 10 minutes on Sunday at 02:00 UTC.",
                          isRead: true, createdAt: .now.addingTimeInterval(-90_000)),
    ])
    return NavigationStack { InboxView(model: model) }
        .environment(AppModel.preview())
}
#endif
