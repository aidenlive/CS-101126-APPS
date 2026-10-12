import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Observation
import StudioKit
import CardsiteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The workspace's uploads, for picking an image or file into a field, with
/// a way to add a new one. Mirrors the web's UploadPicker.
@MainActor
@Observable
final class UploadPickerModel {
    /// The image types the server accepts for `type=image` (UploadRules).
    static let imageTypes: [UTType] = [.jpeg, .png, .gif, .webP]

    let list: PagedListModel<UploadItem>
    let imagesOnly: Bool
    private let client: APIClient
    private(set) var isUploading = false
    var uploadError: String?
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient, imagesOnly: Bool) {
        self.client = client
        self.imagesOnly = imagesOnly
        self.list = PagedListModel { page in try await client.uploads(page: page, kind: imagesOnly ? .image : nil) }
    }

    /// Uploads bytes and returns the stored upload, or nil after showing why not.
    func upload(_ data: Data, filename: String, contentType: UTType?) async -> UploadItem? {
        uploadError = nil
        var data = data
        var filename = filename
        var type = contentType ?? UTType(filenameExtension: (filename as NSString).pathExtension)
        let isImage = type?.conforms(to: .image) ?? false

        // HEIC and other image types the server refuses become JPEG.
        if isImage, let current = type, !Self.imageTypes.contains(where: { current.conforms(to: $0) }) {
            guard let jpeg = await Self.jpeg(from: data) else {
                uploadError = String(localized: "This image couldn't be read. Try a JPEG or PNG.")
                return nil
            }
            data = jpeg
            type = .jpeg
            filename = ((filename as NSString).deletingPathExtension) + ".jpg"
        }
        if imagesOnly && !isImage {
            uploadError = String(localized: "Choose an image: JPEG, PNG, GIF or WebP.")
            return nil
        }
        guard Int64(data.count) <= UploadRules.maxBytes else {
            uploadError = String(localized: "Choose a file under 10 MB.")
            return nil
        }

        isUploading = true
        defer { isUploading = false }
        do {
            let file = MultipartFile(
                filename: filename,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                data: data
            )
            let upload = try await client.upload(file, as: isImage ? .image : .file)
            list.insert(upload)
            return upload
        } catch {
            onError(error)
            uploadError = error.asAPIError.localizedDescription
            return nil
        }
    }

    private static func jpeg(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            #if canImport(UIKit)
            return UIImage(data: data)?.jpegData(compressionQuality: 0.9)
            #elseif canImport(AppKit)
            guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            #else
            return nil
            #endif
        }.value
    }
}

struct UploadPickerSheet: View {
    @Environment(PagesModel.self) private var pages
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let imagesOnly: Bool
    let onPick: (UploadItem) -> Void

    @State private var model: UploadPickerModel? = nil
    @State private var photo: PhotosPickerItem? = nil
    @State private var isImporting = false
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 112

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.studioBg)
            .navigationTitle(imagesOnly ? Text("Choose an Image") : Text("Choose a File"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
        }
        .task {
            if model == nil {
                let model = UploadPickerModel(client: pages.client, imagesOnly: imagesOnly)
                model.onError = app.handle
                self.model = model
            }
            if let model { await model.list.loadIfNeeded() }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: imagesOnly ? UploadPickerModel.imageTypes + [.heic] : [.item]
        ) { result in
            if case .success(let url) = result {
                Task { await importFile(url) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var addMenu: some View {
        if model?.isUploading == true {
            ProgressView()
                .accessibilityLabel("Uploading")
        } else {
            Menu {
                if imagesOnly {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                }
                Button {
                    isImporting = true
                } label: {
                    Label(imagesOnly ? String(localized: "Choose Image File…") : String(localized: "Choose File…"),
                          systemImage: "folder")
                }
            } label: {
                Label("Upload New", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func content(_ model: UploadPickerModel) -> some View {
        VStack(spacing: 0) {
            if let message = model.uploadError {
                StudioBanner(lead: String(localized: "Not uploaded."), message: message, tone: .error)
                    .padding(StudioSpace.s4)
            }
            ListStateView(
                state: model.list.state,
                empty: .init(
                    systemImage: imagesOnly ? "photo.on.rectangle" : "folder",
                    title: imagesOnly ? String(localized: "No images yet") : String(localized: "No uploads yet"),
                    message: String(localized: "Upload one here and it is stored in this workspace, ready to reuse.")
                ),
                retry: { [list = model.list] in await list.refresh() }
            ) { uploads in
                ScrollView {
                    if let error = model.list.refreshError {
                        RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                            .padding(.horizontal, StudioSpace.s4)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: StudioSpace.s3)],
                              spacing: StudioSpace.s3) {
                        ForEach(uploads) { upload in
                            Button {
                                onPick(upload)
                                dismiss()
                            } label: {
                                UploadTile(upload: upload)
                            }
                            .buttonStyle(StudioPressStyle(scale: 0.97))
                        }
                    }
                    .padding(StudioSpace.s4)
                    if model.list.hasMore {
                        ProgressView()
                            .padding(StudioSpace.s4)
                            .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
                    }
                }
                .refreshable { [list = model.list] in await list.refresh() }
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let model else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first
            let name = "photo." + (type?.preferredFilenameExtension ?? "jpg")
            if let upload = await model.upload(data, filename: name, contentType: type) {
                onPick(upload)
                dismiss()
            }
        } catch {
            model.uploadError = String(localized: "This photo couldn't be read.")
        }
    }

    private func importFile(_ url: URL) async {
        guard let model else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            let type = UTType(filenameExtension: url.pathExtension)
            if let upload = await model.upload(data, filename: url.lastPathComponent, contentType: type) {
                onPick(upload)
                dismiss()
            }
        } catch {
            model.uploadError = String(localized: "This file couldn't be read.")
        }
    }
}

private struct UploadTile: View {
    let upload: UploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Color.studioSurface3
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if upload.isImage, let url = URL(string: upload.url) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo").foregroundStyle(Color.studioText4)
                            }
                        }
                    } else {
                        Image(systemName: "doc")
                            .imageScale(.large)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
            Text(upload.displayName)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(ByteCountFormatter.string(fromByteCount: upload.size, countStyle: .file))
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Uses this upload")
    }
}
