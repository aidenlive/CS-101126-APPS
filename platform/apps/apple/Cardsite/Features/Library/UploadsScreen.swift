import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import StudioKit
import CardsiteKit

/// The root for the registry: its own navigation stack.
struct UploadsScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            UploadsView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

/// Images as a gallery, other files as a list. Add from Photos or Files (up
/// to 10 MB), copy an address, delete.
struct UploadsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: UploadsModel
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isImportingFile = false
    @State private var isPickingPhoto = false
    @State private var pendingDelete: UploadItem? = nil
    @State private var errorMessage: String? = nil

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: UploadsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: UploadsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: model.filter == .all ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle",
                title: model.filter == .all
                    ? String(localized: "No uploads yet")
                    : String(localized: "Nothing of this kind yet"),
                message: String(localized: "Add an image or a file and it appears here, ready to re-use."),
                actionTitle: String(localized: "Upload"),
                action: { isImportingFile = true }
            ),
            retry: { [model] in await model.refresh() }
        ) { _ in
            gallery
        }
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .navigationTitle("Uploads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isUploading {
                    ProgressView()
                        .accessibilityLabel("Uploading")
                } else {
                    Menu {
                        Button {
                            isPickingPhoto = true
                        } label: {
                            Label("Photo Library…", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            isImportingFile = true
                        } label: {
                            Label("Choose File…", systemImage: "folder")
                        }
                    } label: {
                        Label("Upload", systemImage: "plus")
                    }
                }
            }
        }
        .task { [model] in await model.loadIfNeeded() }
        // Uploads belong to the workspace: reload when the switcher changes it.
        .onChange(of: app.workspaceScope) { _, _ in Task { await model.refresh() } }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await uploadPhoto(item) }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: UploadCandidate.importableTypes) { result in
            switch result {
            case .success(let url): Task { await uploadFile(at: url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Delete this upload?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete \(item.displayName)", role: .destructive) { Task { await delete(item) } }
        } message: { _ in
            Text("Anything that uses its address will stop showing it.")
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Pieces

    private var filterBar: some View {
        HStack(spacing: StudioSpace.s3) {
            Picker("Show", selection: Binding(
                get: { model.filter },
                set: { filter in Task { await model.setFilter(filter) } }
            )) {
                Text("All").tag(UploadsModel.Filter.all)
                Text("Images").tag(UploadsModel.Filter.images)
                Text("Files").tag(UploadsModel.Filter.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: StudioSpace.s2)

            if let bytes = model.storageBytes {
                Text("\(bytes.formatted(.byteCount(style: .file))) used")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Storage used: \(bytes.formatted(.byteCount(style: .file)))"))
            }
        }
        .padding(.horizontal, StudioSpace.s4)
        .padding(.vertical, StudioSpace.s2)
        .background(Color.studioBg)
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpace.s6) {
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                }

                if !model.images.isEmpty {
                    VStack(alignment: .leading, spacing: StudioSpace.s3) {
                        StudioSectionHeader(String(localized: "Images"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: StudioSpace.s16 * 2), spacing: StudioSpace.s3)],
                                  spacing: StudioSpace.s3) {
                            ForEach(model.images) { item in
                                LibraryImageTile(item: item)
                                    .contextMenu { menu(for: item) }
                            }
                        }
                    }
                }

                if !model.files.isEmpty {
                    VStack(alignment: .leading, spacing: StudioSpace.s3) {
                        StudioSectionHeader(String(localized: "Files"))
                        StudioCard(flush: true) {
                            VStack(spacing: 0) {
                                ForEach(model.files) { item in
                                    LibraryFileRow(item: item) { menu(for: item) }
                                    if item.id != model.files.last?.id {
                                        Divider().padding(.leading, StudioSpace.s4)
                                    }
                                }
                            }
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
            .padding(StudioSpace.s4)
            .readableWidth(960)
        }
        .background(Color.studioBg)
        .refreshable { [model] in await model.refresh() }
    }

    @ViewBuilder
    private func menu(for item: UploadItem) -> some View {
        Button {
            Pasteboard.copy(item.url)
            Haptics.success()
        } label: {
            Label("Copy Address", systemImage: "doc.on.doc")
        }
        if let address = item.address {
            ShareLink(item: address) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Link(destination: address) {
                Label("Open", systemImage: "safari")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = item } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    // MARK: Actions

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = String(localized: "That photo couldn't be read.")
                return
            }
            let candidate = try UploadCandidate.fromPhoto(data: data, contentType: item.supportedContentTypes.first)
            try await model.upload(candidate)
            Haptics.success()
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    private func uploadFile(at url: URL) async {
        do {
            let candidate = try UploadCandidate.fromFile(at: url)
            try await model.upload(candidate)
            Haptics.success()
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    private func delete(_ item: UploadItem) async {
        do {
            try await model.delete(item)
        } catch {
            errorMessage = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

/// A square image with its name and size beneath.
struct LibraryImageTile: View {
    let item: UploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Color.studioSurface2
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncImage(url: item.address) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .imageScale(.large)
                                .foregroundStyle(Color.studioText3)
                        default:
                            ProgressView()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .strokeBorder(Color.studioBorder, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.displayName)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.size.formatted(.byteCount(style: .file)))
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.displayName))
        .accessibilityValue(Text(item.size.formatted(.byteCount(style: .file))))
        .accessibilityAddTraits(.isImage)
    }
}

/// Leading document glyph, name and meta, trailing actions menu.
struct LibraryFileRow<MenuContent: View>: View {
    let item: UploadItem
    @ViewBuilder let menu: () -> MenuContent

    private var glyph: String {
        switch item.mimeType {
        case "application/pdf": return "doc.richtext"
        case "application/zip": return "doc.zipper"
        case "text/csv": return "tablecells"
        case "application/json": return "curlybraces"
        default: return "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: glyph)
                .imageScale(.large)
                .foregroundStyle(Color.studioText3)
                .frame(width: StudioSpace.s8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: item.displayName)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: StudioSpace.s2)
            Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel(Text("Actions for \(item.displayName)"))
        }
        .padding(StudioSpace.s4)
        .contextMenu { menu() }
    }

    private var meta: String {
        var parts = [item.size.formatted(.byteCount(style: .file)), item.fileExtension.uppercased()]
        if let date = item.createdAt { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Uploads") {
    let model = UploadsModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed([
        UploadItem(id: 3, name: "a.png", originalName: "storefront.png", fileExtension: "png", mimeType: "image/png",
                   size: 248_000, type: "image", url: "https://picsum.photos/id/42/400", createdAt: .now),
        UploadItem(id: 4, name: "b.jpg", originalName: "team-photo.jpg", fileExtension: "jpg", mimeType: "image/jpeg",
                   size: 1_204_000, type: "image", url: "https://picsum.photos/id/64/400", createdAt: .now),
        UploadItem(id: 5, name: "c.pdf", originalName: "spring-menu.pdf", fileExtension: "pdf",
                   mimeType: "application/pdf", size: 640_000, type: "file", url: "https://example.com/c.pdf",
                   createdAt: .now.addingTimeInterval(-86_400)),
    ], storageBytes: 2_092_000)
    return NavigationStack { UploadsView(model: model) }
        .environment(AppModel.preview())
}
#endif
