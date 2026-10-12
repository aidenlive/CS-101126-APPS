import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Sign-ins and security changes on the account (`/logs`), searchable on
/// the server and filterable by device.
@MainActor
@Observable
final class ActivityLogsModel {
    /// Replaced when the search or filter changes: the server does both.
    private(set) var list: PagedListModel<ActivityLogEntry>
    private(set) var appliedSearch = ""
    private(set) var device: LogDeviceType?
    var searchText = ""

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = ActivityLogsModel.makeList(client: client, search: "", device: nil)
        self.list.onError = onError
    }

    private static func makeList(client: APIClient, search: String, device: LogDeviceType?) -> PagedListModel<ActivityLogEntry> {
        PagedListModel { page in try await client.activityLogs(page: page, search: search, device: device) }
    }

    var isFiltered: Bool { !appliedSearch.isEmpty || device != nil }

    func applySearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != appliedSearch else { return }
        appliedSearch = trimmed
        await reload()
    }

    func setDevice(_ device: LogDeviceType?) async {
        guard device != self.device else { return }
        self.device = device
        await reload()
    }

    private func reload() async {
        let next = Self.makeList(client: client, search: appliedSearch, device: device)
        next.onError = onError
        list = next
        await next.refresh()
    }

    /// Sample data for previews; skips the first fetch.
    func seed(_ entries: [ActivityLogEntry]) {
        for entry in entries.reversed() { list.insert(entry) }
    }
}

extension ActivityLogEntry {
    /// Friendly names for the event types seen; anything else as sent.
    var typeTitle: String {
        switch type {
        case "login": return String(localized: "Signed in")
        case "login.recovery_code": return String(localized: "Signed in with a recovery code")
        case "twofa.enabled": return String(localized: "Two-factor turned on")
        case "twofa.disabled": return String(localized: "Two-factor turned off")
        case "twofa.recovery_codes_regenerated": return String(localized: "Recovery codes replaced")
        default: return type.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " · ")
        }
    }

    var deviceSymbol: String {
        switch deviceType {
        case "mobile": return "iphone"
        case "tablet": return "ipad"
        default: return "desktopcomputer"
        }
    }
}

/// The root for the registry: its own navigation stack.
struct ActivityLogsScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ActivityLogsView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

struct ActivityLogsView: View {
    @State private var model: ActivityLogsModel

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: ActivityLogsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: ActivityLogsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: model.isFiltered ? "magnifyingglass" : "list.bullet.rectangle",
                title: model.isFiltered
                    ? String(localized: "No matching activity")
                    : String(localized: "No activity logs found"),
                message: model.isFiltered
                    ? String(localized: "Try another search or device.")
                    : String(localized: "Sign-ins and account activity will appear here.")
            ),
            skeleton: .textRows,
            retry: { [list = model.list] in await list.refresh() }
        ) { entries in
            List {
                ListPageHead(kicker: String(localized: "Account"),
                             title: String(localized: "Activity Logs"),
                             description: String(localized: "Sign-ins and security changes on your account."))
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                        .studioClearRow()
                }
                ForEach(entries) { entry in
                    ActivityLogRow(entry: entry)
                        .contextMenu {
                            if !entry.ip.isEmpty {
                                Button {
                                    Pasteboard.copy(entry.ip)
                                } label: {
                                    Label("Copy IP Address", systemImage: "doc.on.doc")
                                }
                            }
                        }
                }
                .studioRowBackground()
                if model.list.hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .studioClearRow()
                    .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
                }
            }
            .studioList()
            .refreshable { [list = model.list] in await list.refresh() }
        }
        .background(Color.studioBg)
        .navigationTitle("Activity Logs")
        .inlineNavigationTitle()
        .searchable(text: $model.searchText, prompt: Text("Search by IP, city, browser…"))
        .onSubmit(of: .search) { Task { await model.applySearch() } }
        .onChange(of: model.searchText) { _, text in
            // Clearing the field shows everything again without a submit.
            if text.isEmpty { Task { await model.applySearch() } }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter by Device Type", selection: Binding(
                        get: { [model] in model.device },
                        set: { [model] device in Task { await model.setDevice(device) } }
                    )) {
                        Text("All Devices").tag(LogDeviceType?.none)
                        Text("Desktop").tag(LogDeviceType?.some(.desktop))
                        Text("Mobile").tag(LogDeviceType?.some(.mobile))
                        Text("Tablet").tag(LogDeviceType?.some(.tablet))
                    }
                } label: {
                    Label("Filter by Device Type",
                          systemImage: model.device == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
    }
}

/// Type and date on top; IP, browser, OS and device beneath.
struct ActivityLogRow: View {
    let entry: ActivityLogEntry

    private var details: String {
        let location = [entry.cityName, entry.countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [entry.browserName, entry.osName, entry.deviceType?.capitalized, location.isEmpty ? nil : location]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Image(systemName: entry.deviceSymbol)
                .foregroundStyle(Color.studioText3)
                .frame(width: StudioSpace.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s2) {
                    Text(entry.typeTitle)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                    Spacer(minLength: StudioSpace.s2)
                    if let date = entry.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .monospacedDigit()
                    }
                }
                if !entry.ip.isEmpty {
                    Text(verbatim: entry.ip)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.studioText2)
                        .textSelection(.enabled)
                }
                if !details.isEmpty {
                    Text(verbatim: details)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Activity logs") {
    let model = ActivityLogsModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed([
        ActivityLogEntry(id: 14, type: "twofa.disabled", ip: "203.0.113.7", deviceType: "desktop", osName: "macOS",
                         browserName: "Safari", countryCode: "GB", cityName: "London", createdAt: .now),
        ActivityLogEntry(id: 13, type: "login.recovery_code", ip: "203.0.113.7", deviceType: "mobile", osName: "iOS",
                         browserName: "Cardsite", createdAt: .now.addingTimeInterval(-3_600)),
        ActivityLogEntry(id: 11, type: "login", ip: "198.51.100.23", deviceType: "tablet", osName: "iPadOS",
                         browserName: "Safari", createdAt: .now.addingTimeInterval(-86_400)),
    ])
    return NavigationStack { ActivityLogsView(model: model) }
        .environment(AppModel.preview())
}
#endif
