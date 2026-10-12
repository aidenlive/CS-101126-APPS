import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Form submissions collected by bio page blocks, filtered by kind.
@MainActor
@Observable
final class DataRecordsModel {
    /// Replaced when the filter changes: the server filters by `type`.
    private(set) var list: PagedListModel<DataRecord>
    private(set) var kind: DataRecordKind?

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = DataRecordsModel.makeList(client: client, kind: nil)
        self.list.onError = onError
    }

    private static func makeList(client: APIClient, kind: DataRecordKind?) -> PagedListModel<DataRecord> {
        PagedListModel { page in try await client.dataRecords(page: page, kind: kind) }
    }

    func setKind(_ kind: DataRecordKind?) async {
        guard kind != self.kind else { return }
        self.kind = kind
        let next = Self.makeList(client: client, kind: kind)
        next.onError = onError
        list = next
        await next.refresh()
    }

    func delete(_ record: DataRecord) async throws {
        do {
            try await client.deleteDataRecord(id: record.id)
            list.remove(id: record.id)
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetch.
    func seed(_ records: [DataRecord]) {
        for record in records.reversed() { list.insert(record) }
    }
}

extension DataRecord {
    /// "Contact", "Mail", "Phone" (the web's filter names), else the raw type.
    var kindTitle: String {
        switch DataRecordKind(rawValue: type) {
        case .contact: return String(localized: "Contact")
        case .mail: return String(localized: "Mail")
        case .phone: return String(localized: "Phone")
        case nil: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var kindSymbol: String {
        switch DataRecordKind(rawValue: type) {
        case .contact: return "person.text.rectangle"
        case .mail: return "envelope"
        case .phone: return "phone"
        case nil: return "tray.full"
        }
    }

    /// The most telling value for the row: email, phone, then name.
    var headline: String {
        for key in ["email", "phone", "name"] {
            if let value = data[key]?.stringValue, !value.isEmpty { return value }
        }
        return fields.first?.value ?? String(localized: "Record \(id)")
    }
}

/// The root for the registry: its own navigation stack.
struct DataRecordsScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            DataRecordsView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

struct DataRecordsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: DataRecordsModel
    @State private var pendingDelete: DataRecord?
    @State private var deleteError: String?

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: DataRecordsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: DataRecordsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "tray.full",
                title: String(localized: "No data records yet"),
                message: String(localized: "Records are created when visitors submit forms on your bio page blocks.")
            ),
            retry: { [list = model.list] in await list.refresh() }
        ) { records in
            List {
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                        .listRowSeparator(.hidden)
                }
                ForEach(records) { record in
                    NavigationLink {
                        DataRecordDetailView(record: record) { pendingDelete = record }
                    } label: {
                        DataRecordRow(record: record)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = record } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = record } label: {
                            Label("Delete…", systemImage: "trash")
                        }
                    }
                }
                if model.list.hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
                }
            }
            .refreshable { await model.list.refresh() }
        }
        .navigationTitle("Data Records")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter by record type", selection: Binding(
                        get: { model.kind },
                        set: { kind in Task { await model.setKind(kind) } }
                    )) {
                        Text("All Types").tag(DataRecordKind?.none)
                        Text("Contact").tag(DataRecordKind?.some(.contact))
                        Text("Mail").tag(DataRecordKind?.some(.mail))
                        Text("Phone").tag(DataRecordKind?.some(.phone))
                    }
                } label: {
                    Label("Filter by record type",
                          systemImage: model.kind == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        // Records belong to the workspace: reload when the switcher changes it.
        .onChange(of: app.workspaceScope) { _, _ in Task { await model.list.refresh() } }
        .confirmationDialog(
            "Delete this record?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { record in
            Button("Delete Record", role: .destructive) { Task { await delete(record) } }
        } message: { _ in
            Text("The submission is removed for everyone in this workspace. This can't be undone.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func delete(_ record: DataRecord) async {
        do {
            try await model.delete(record)
            Haptics.success()
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

struct DataRecordRow: View {
    let record: DataRecord

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: record.kindSymbol)
                .foregroundStyle(Color.studioText3)
                .frame(width: StudioSpace.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(spacing: StudioSpace.s2) {
                    Text(verbatim: record.headline)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    StudioStatusPill(record.kindTitle, tone: .accent)
                }
                HStack(spacing: StudioSpace.s2) {
                    Text(verbatim: record.fields.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                        .lineLimit(1)
                    Spacer(minLength: StudioSpace.s2)
                    if let date = record.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .monospacedDigit()
                    }
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
    }
}

/// Every submitted field, with emails and phone numbers one tap away.
struct DataRecordDetailView: View {
    let record: DataRecord
    let requestDelete: () -> Void

    var body: some View {
        Form {
            Section("Submitted") {
                if record.fields.isEmpty {
                    Text("This submission has no fields.")
                        .studioText(.uiSm)
                        .studioMuted()
                }
                ForEach(record.fields) { field in
                    LabeledContent {
                        value(for: field.key, field.value)
                    } label: {
                        Text(verbatim: field.key.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    .contextMenu {
                        Button {
                            Pasteboard.copy(field.value)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Type", value: record.kindTitle)
                if let date = record.createdAt {
                    LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Record", value: "#\(record.id)")
            }

            Section {
                Button("Delete Record…", role: .destructive, action: requestDelete)
            }
        }
        .studioForm()
        .navigationTitle(record.kindTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func value(for key: String, _ value: String) -> some View {
        if key.lowercased().contains("email"), value.contains("@"), let url = URL(string: "mailto:\(value)") {
            Link(value, destination: url)
        } else if key.lowercased().contains("phone"),
                  let url = URL(string: "tel:\(value.filter { $0.isNumber || $0 == "+" })") {
            Link(value, destination: url)
        } else {
            Text(verbatim: value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if DEBUG
#Preview("Data records") {
    let model = DataRecordsModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed([
        DataRecord(id: 3, biolinkBlockID: 9, linkID: 24, type: "email_collector",
                   data: ["email": "grace@example.test", "name": "Grace"], createdAt: .now),
        DataRecord(id: 2, biolinkBlockID: 10, linkID: 24, type: "phone_collector",
                   data: ["phone": "+44 20 7946 0000", "name": "Alan"], createdAt: .now.addingTimeInterval(-86_400)),
    ])
    return NavigationStack { DataRecordsView(model: model) }
        .environment(AppModel.preview())
}
#endif
