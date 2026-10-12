import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Retargeting pixels links and bio pages can carry: list, create, edit,
/// delete. The web's `/pixels`.
@MainActor
@Observable
final class PixelsModel {
    let list: PagedListModel<TrackingPixel>
    /// The providers, for names, field labels and which ones can emit.
    private(set) var types: Loadable<[PixelType]> = .idle
    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = PagedListModel { page in try await client.pixels(page: page) }
        self.list.onError = onError
    }

    /// The provider list changes only with a server release; once is enough.
    func loadTypes(force: Bool = false) async {
        if !force, types.value != nil { return }
        if types.value == nil { types = .loading }
        do {
            types = .loaded(try await client.pixelTypes())
        } catch is CancellationError {
            if case .loading = types { types = .idle }
        } catch {
            onError(error)
            if types.value == nil { types = .failed(error.asAPIError) }
        }
    }

    func type(for key: String) -> PixelType? {
        types.value?.first { $0.key == key }
    }

    /// The provider's name, or the web's fallback for one the list doesn't know.
    func typeName(for key: String) -> String {
        type(for: key)?.name ?? PixelType.fallbackName(for: key)
    }

    /// Creates a pixel, or saves `pixel` with the new values.
    func save(_ input: PixelInput, editing pixel: TrackingPixel?) async throws -> TrackingPixel {
        do {
            if let pixel {
                let saved = try await client.updatePixel(id: pixel.id, input)
                list.replace(saved)
                return saved
            }
            let created = try await client.createPixel(input)
            list.insert(created)
            return created
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ pixel: TrackingPixel) async throws {
        do {
            try await client.deletePixel(id: pixel.id)
            list.remove(id: pixel.id)
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetches. An empty list
    /// shows the empty state.
    func seed(_ pixels: [TrackingPixel], types: [PixelType]) {
        for pixel in pixels.reversed() { list.insert(pixel) }
        if pixels.isEmpty {
            list.insert(TrackingPixel(id: -1, type: "", name: "", pixel: ""))
            list.remove(id: -1)
        }
        self.types = .loaded(types)
    }
}

/// The registry's `.more` destination: stack-free.
struct PixelsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: PixelsModel
    @State private var editing: PixelEditorTarget? = nil
    @State private var pendingDelete: TrackingPixel? = nil

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: PixelsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: PixelsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "scope",
                title: String(localized: "No tracking pixels yet"),
                message: String(localized: "Add one to start tracking conversions."),
                actionTitle: String(localized: "Create Pixel"),
                action: { editing = .new }
            ),
            retry: { [list = model.list] in await list.refresh() }
        ) { pixels in
            List {
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(pixels.enumerated()), id: \.element.id) { index, pixel in
                        Button {
                            editing = .existing(pixel)
                        } label: {
                            PixelRow(pixel: pixel, typeName: model.typeName(for: pixel.type),
                                     canEmit: model.type(for: pixel.type)?.emitsBeacon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("org.pixels.row.\(index)")
                        .accessibilityHint(Text("Edits the pixel"))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = pixel } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editing = .existing(pixel) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        .contextMenu {
                            Button { editing = .existing(pixel) } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            Button { Pasteboard.copy(pixel.pixel) } label: {
                                Label("Copy ID", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) { pendingDelete = pixel } label: {
                                Label("Delete…", systemImage: "trash")
                            }
                        }
                    }
                    OrganiseLoadMoreRow(list: model.list)
                } footer: {
                    Text("Pixels emit on your public pages as the provider's own no-script beacon. Providers marked “Can't emit yet” have none, so they count nothing for now.")
                }
            }
            .refreshable { [list = model.list] in await list.refresh() }
        }
        .navigationTitle("Pixels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: {
                    Label("Create Pixel", systemImage: "plus")
                }
                .accessibilityIdentifier("org.pixels.create")
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        // Separate, so a provider list that fails never holds up the pixels.
        .task { [model] in await model.loadTypes() }
        .onChange(of: app.workspaceScope) { _, _ in Task { await model.list.refresh() } }
        .sheet(item: $editing) { target in
            PixelEditorSheet(model: model, pixel: target.pixel)
        }
        .organiseDeleteFlow(
            $pendingDelete,
            title: String(localized: "Delete this pixel?"),
            confirmTitle: { String(localized: "Delete \($0.name)") },
            message: String(localized: "Are you sure you want to delete this pixel? This can't be undone."),
            delete: { [model] pixel in try await model.delete(pixel) }
        )
    }
}

enum PixelEditorTarget: Identifiable, Hashable {
    case new
    case existing(TrackingPixel)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let pixel): return "pixel-\(pixel.id)"
        }
    }

    var pixel: TrackingPixel? {
        if case .existing(let pixel) = self { return pixel }
        return nil
    }
}

/// Name and provider, then the id and when it was added. A provider with no
/// beacon is marked, as the web's pixel picker marks it.
struct PixelRow: View {
    let pixel: TrackingPixel
    let typeName: String
    /// nil while the provider list is unknown.
    let canEmit: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Image(systemName: "scope")
                .foregroundStyle(Color.studioText2)
                .frame(width: StudioSpace.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(verbatim: pixel.name)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                let pills = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s1))
                    : AnyLayout(HStackLayout(spacing: StudioSpace.s2))
                pills {
                    StudioStatusPill(typeName, tone: .accent)
                    if canEmit == false {
                        StudioStatusPill(String(localized: "Can't emit yet"), tone: .warning)
                    }
                }
                Text(verbatim: pixel.pixel)
                    .studioText(.mono)
                    .foregroundStyle(Color.studioText2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let added = organiseAddedLine(pixel.createdAt) {
                    Text(added)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            Spacer(minLength: StudioSpace.s2)
            Image(systemName: "chevron.right")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, StudioSpace.s1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor

/// Name, provider (from `/pixels/types`) and the id, labelled the way the
/// provider names it.
struct PixelEditorSheet: View {
    let model: PixelsModel
    let pixel: TrackingPixel?

    @Environment(\.dismiss) private var dismiss
    @State private var input: PixelInput
    @State private var error: String? = nil
    @State private var isSaving = false

    /// The web's default provider for a new pixel.
    private static let defaultType = "facebook"

    init(model: PixelsModel, pixel: TrackingPixel?) {
        self.model = model
        self.pixel = pixel
        _input = State(initialValue: pixel.map(PixelInput.init) ?? PixelInput(name: "", type: Self.defaultType, pixel: ""))
    }

    private var original: PixelInput {
        pixel.map(PixelInput.init) ?? PixelInput(name: "", type: Self.defaultType, pixel: "")
    }

    private var selectedType: PixelType? { model.type(for: input.type) }
    private var isDirty: Bool { input != original }
    private var canSave: Bool {
        !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !input.pixel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !input.type.isEmpty && isDirty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditorTextField(String(localized: "Name"), text: $input.name,
                                    prompt: String(localized: "My Facebook Pixel"))
                        .accessibilityIdentifier("org.pixels.editor.name")
                } footer: {
                    Text("A tracking pixel you can attach to any link.")
                }
                .editorRowBackground()

                Section {
                    typePicker
                } header: {
                    EditorSectionHeader(String(localized: "Type"))
                } footer: {
                    typeFooter
                }
                .editorRowBackground()

                Section {
                    EditorTextField(
                        selectedType.map { $0.fieldLabel.isEmpty ? String(localized: "Pixel ID / Code") : $0.fieldLabel }
                            ?? String(localized: "Pixel ID / Code"),
                        text: $input.pixel,
                        prompt: selectedType.map { $0.description.isEmpty ? String(localized: "Enter pixel ID or tracking code") : $0.description }
                            ?? String(localized: "Enter pixel ID or tracking code"),
                        kind: .plain,
                        error: error
                    )
                    .accessibilityIdentifier("org.pixels.editor.code")
                    .onSubmit { Task { await save() } }
                }
                .editorRowBackground()
            }
            .resourceEditorForm()
            .navigationTitle(pixel == nil ? String(localized: "Create pixel") : String(localized: "Edit pixel"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Saving"))
                    } else {
                        Button(pixel == nil ? String(localized: "Create") : String(localized: "Save")) {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityIdentifier("org.pixels.editor.save")
                    }
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .task { [model] in await model.loadTypes() }
        }
        .organiseSheetFrame()
    }

    @ViewBuilder
    private var typePicker: some View {
        switch model.types {
        case .idle, .loading:
            HStack(spacing: StudioSpace.s2) {
                ProgressView().controlSize(.small)
                Text("Loading providers…")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(failure.localizedDescription)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { Task { await model.loadTypes(force: true) } }
            }
        case .loaded(let types):
            Picker("Type", selection: $input.type) {
                ForEach(types) { type in
                    Text(type.name).tag(type.key)
                }
                // A provider the server no longer lists stays selectable,
                // so editing an old pixel never changes its type silently.
                if !input.type.isEmpty, !types.contains(where: { $0.key == input.type }) {
                    Text(PixelType.fallbackName(for: input.type)).tag(input.type)
                }
            }
        }
    }

    @ViewBuilder
    private var typeFooter: some View {
        if let selectedType {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                if !selectedType.description.isEmpty {
                    Text(selectedType.description)
                }
                if selectedType.emitsBeacon {
                    Text("Emits on your public pages, as the provider's own no-script beacon.")
                } else {
                    Label {
                        Text("Can't emit yet: this provider has no beacon that works without scripts, so it counts nothing on your pages for now.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.studioWarning)
                    }
                }
            }
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            _ = try await model.save(input, editing: pixel)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Pixels") {
    let model = PixelsModel(client: OrganisePreviewData.client)
    model.seed(OrganisePreviewData.pixels, types: OrganisePreviewData.pixelTypes)
    return NavigationStack { PixelsView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Pixels, empty") {
    let model = PixelsModel(client: OrganisePreviewData.client)
    model.seed([], types: OrganisePreviewData.pixelTypes)
    return NavigationStack { PixelsView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Edit pixel") {
    let model = PixelsModel(client: OrganisePreviewData.client)
    model.seed(OrganisePreviewData.pixels, types: OrganisePreviewData.pixelTypes)
    return PixelEditorSheet(model: model, pixel: OrganisePreviewData.pixels[0])
}
#endif
