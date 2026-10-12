import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// `GET/PUT /account/preferences`. The PUT replaces the stored object, so
/// the draft starts from everything the server sent — including the OpenAI
/// key and white-label settings, which are edited on the web only (N10) —
/// and is sent back whole.
@MainActor
@Observable
final class PreferencesModel {
    private(set) var state: Loadable<AccountPreferences> = .idle
    private(set) var refreshError: APIError?
    private(set) var isSaving = false
    private(set) var didSave = false
    var draft = AccountPreferences()

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
    }

    var hasChanges: Bool {
        guard let saved = state.value else { return false }
        return saved != draft
    }

    func loadIfNeeded() async {
        if case .idle = state { await refresh() }
    }

    /// Keeps unsaved edits: the draft is replaced only when it matches what
    /// was loaded before.
    func refresh() async {
        if state.value == nil { state = .loading }
        do {
            let fresh = try await client.preferences()
            if !hasChanges { draft = fresh }
            state = .loaded(fresh)
            refreshError = nil
        } catch is CancellationError {
            if case .loading = state { state = .idle }
        } catch {
            onError(error)
            if state.value == nil {
                state = .failed(error.asAPIError)
            } else {
                refreshError = error.asAPIError
            }
        }
    }

    func dismissRefreshError() { refreshError = nil }

    func save() async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        // Excluded IPs: trim each line and drop blanks, as a list should read.
        draft.excludedIPs = draft.excludedIPs
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        do {
            let saved = try await client.updatePreferences(draft)
            draft = saved
            state = .loaded(saved)
            didSave = true
        } catch {
            onError(error)
            throw error
        }
    }

    func acknowledgeSave() { didSave = false }

    /// Sample data for previews; skips the first fetch.
    func seed(_ preferences: AccountPreferences) {
        state = .loaded(preferences)
        draft = preferences
    }
}

/// The root for the registry: its own navigation stack.
struct PreferencesScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            PreferencesView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

struct PreferencesView: View {
    @State private var model: PreferencesModel
    @State private var saveError: String? = nil
    /// The Mac Settings window has no navigation toolbar, so Save sits at
    /// the foot of the form there.
    private let inlineSave: Bool

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void, inlineSave: Bool = false) {
        _model = State(initialValue: PreferencesModel(client: client, onError: onError))
        self.inlineSave = inlineSave
    }

    /// For previews.
    init(model: PreferencesModel, inlineSave: Bool = false) {
        _model = State(initialValue: model)
        self.inlineSave = inlineSave
    }

    private static let perPageOptions = [10, 25, 50, 100]
    private struct OrderField: Identifiable {
        let id: String
        let title: LocalizedStringKey
    }

    private static let orderFields: [OrderField] = [
        OrderField(id: AccountPreferences.Key.linksOrderBy, title: "Short links"),
        OrderField(id: AccountPreferences.Key.biolinksOrderBy, title: "Bio pages"),
        OrderField(id: AccountPreferences.Key.qrCodesOrderBy, title: "QR codes"),
        OrderField(id: AccountPreferences.Key.pixelsOrderBy, title: "Pixels"),
        OrderField(id: AccountPreferences.Key.projectsOrderBy, title: "Projects"),
        OrderField(id: AccountPreferences.Key.domainsOrderBy, title: "Domains"),
    ]

    var body: some View {
        content
            .navigationTitle("Preferences")
            .toolbar {
                if !inlineSave {
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
            }
            .task { [model] in await model.loadIfNeeded() }
            .onChange(of: model.draft) { _, _ in model.acknowledgeSave() }
            .alert("Couldn’t save preferences",
                   isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading")
        case .failed(let error):
            ErrorStateView(error: error) { [model] in await model.refresh() }
        case .loaded:
            // The Mac Settings window keeps the system look; in the app the
            // form sits on the Studio page like every other.
            if inlineSave {
                form.formStyle(.grouped)
            } else {
                form.studioForm()
            }
        }
    }

    private var form: some View {
        @Bindable var model = model
        return Form {
            if let error = model.refreshError {
                RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                    .studioClearRow()
            }

            Section("Display defaults") {
                Picker("Results per page", selection: $model.draft.resultsPerPage) {
                    ForEach(Self.perPageOptions, id: \.self) { count in
                        Text("\(count) per page").tag(count)
                    }
                    // A stored size outside the four options still shows.
                    if !Self.perPageOptions.contains(model.draft.resultsPerPage) {
                        Text("\(model.draft.resultsPerPage) per page").tag(model.draft.resultsPerPage)
                    }
                }
                Picker("Default sort order", selection: $model.draft.orderType) {
                    Text("Newest first (Descending)").tag("DESC")
                    Text("Oldest first (Ascending)").tag("ASC")
                }
            }
            .listRowBackground(inlineSave ? nil : Color.studioSurface)

            Section("Default sort field per resource") {
                ForEach(Self.orderFields) { field in
                    Picker(field.title, selection: Binding(
                        get: { [model] in model.draft.orderBy(field.id) },
                        set: { [model] in model.draft.setOrderBy($0, for: field.id) }
                    )) {
                        Text("Date created").tag("datetime")
                        Text("Date updated").tag("last_datetime")
                        Text("Clicks").tag("clicks")
                        Text("URL / Name").tag("url")
                    }
                }
            }
            .listRowBackground(inlineSave ? nil : Color.studioSurface)

            Section("Link behavior") {
                Toggle("Auto-copy short link after creation", isOn: $model.draft.autoCopyLink)
                Toggle("Auto-save link settings on change", isOn: $model.draft.autoSaveLinkSettings)
            }
            .listRowBackground(inlineSave ? nil : Color.studioSurface)

            Section {
                TextEditor(text: $model.draft.excludedIPs)
                    .font(.system(.body, design: .monospaced))
                    .plainEntry()
                    .frame(minHeight: StudioSpace.s16 * 2)
                    .accessibilityLabel(Text("Excluded IPs (one per line)"))
            } header: {
                Text("Excluded IPs (one per line)")
            } footer: {
                Text("Clicks from these IPs will not be counted in your statistics.")
            }
            .listRowBackground(inlineSave ? nil : Color.studioSurface)

            Section {
                Text("Your own OpenAI key and white-label settings are managed on cardsite.com.")
                    .studioText(.uiSm)
                    .studioMuted()
            }
            .listRowBackground(inlineSave ? nil : Color.studioSurface)

            if inlineSave {
                Section {
                    HStack {
                        Spacer()
                        saveButton
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(inlineSave ? nil : Color.studioSurface)
            }
        }
        .refreshable { [model] in await model.refresh() }
    }

    @ViewBuilder
    private var saveButton: some View {
        if model.isSaving {
            ProgressView()
        } else {
            Button(model.didSave && !model.hasChanges ? "Saved" : "Save Preferences") {
                Task { await save() }
            }
            .disabled(!model.hasChanges)
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    private func save() async {
        do {
            try await model.save()
            Haptics.success()
        } catch {
            saveError = error.asAPIError.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Preferences") {
    let model = PreferencesModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed(AccountPreferences([
        AccountPreferences.Key.resultsPerPage: 50,
        AccountPreferences.Key.orderType: "DESC",
        AccountPreferences.Key.autoCopyLink: true,
        AccountPreferences.Key.excludedIPs: "192.168.1.1\n10.0.0.1",
    ]))
    return NavigationStack { PreferencesView(model: model) }
        .environment(AppModel.preview())
}
#endif
