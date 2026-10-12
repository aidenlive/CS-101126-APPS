import SwiftUI
import StudioKit
import CardsiteKit

struct QRCodesScreen: View {
    @Environment(QRCodesModel.self) private var model
    @State private var selection: QRCode.ID?
    @State private var isComposing = false
    @State private var pendingDelete: QRCode?
    @State private var deleteError: String?

    var body: some View {
        @Bindable var bindable = model
        NavigationSplitView {
            ListStateView(
                state: model.list.state,
                empty: .init(
                    systemImage: "qrcode",
                    title: String(localized: "No QR codes yet"),
                    message: String(localized: "Make a QR code for a web address or for one of your short links. Point it at a short link and you can change where it goes after it's printed."),
                    actionTitle: String(localized: "New QR Code"),
                    action: { isComposing = true }
                ),
                retry: { [list = model.list] in await list.refresh() }
            ) { _ in
                codeList
            }
            .navigationTitle("QR Codes")
            .searchable(text: $bindable.searchText, prompt: Text("Search QR codes"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isComposing = true } label: {
                        Label("New QR Code", systemImage: "plus")
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
            #endif
        } detail: {
            if let id = selection, let code = model.list.items.first(where: { $0.id == id }) {
                QRCodeDetailView(code: code) { pendingDelete = code }
                    .id(code.id)
            } else {
                ContentUnavailableView("Select a QR code", systemImage: "qrcode",
                                       description: Text("Preview it, then share or save the image."))
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .sheet(isPresented: $isComposing) {
            QRCodeEditorView { code in selection = code.id }
        }
        .confirmationDialog(
            "Delete this QR code?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { code in
            Button("Delete \u{201C}\(code.name)\u{201D}", role: .destructive) {
                Task { await delete(code) }
            }
        } message: { _ in
            Text("This removes it from your workspace. Printed copies keep encoding the same address.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var codeList: some View {
        List(selection: $selection) {
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .listRowSeparator(.hidden)
            }
            if model.visibleCodes.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.visibleCodes) { code in
                NavigationLink(value: code.id) {
                    QRCodeRow(code: code)
                }
                .contextMenu {
                    if let png = code.pngData {
                        ShareLink(item: PNGFile(data: png, name: code.fileName),
                                  preview: SharePreview(code.name, image: Image(systemName: "qrcode"))) {
                            Label("Share Image…", systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { pendingDelete = code } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = code } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if model.list.hasMore, model.searchText.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
            }
        }
        .refreshable { await model.list.refresh() }
    }

    private func delete(_ code: QRCode) async {
        do {
            try await model.delete(code)
            if selection == code.id { selection = nil }
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

struct QRCodeRow: View {
    let code: QRCode

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            QRImage(code: code)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.name)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                Text(verbatim: code.target ?? "")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The server's PNG, scaled without smoothing so modules stay sharp,
/// on a white quiet zone in both appearances (scanners need the contrast).
struct QRImage: View {
    let code: QRCode

    var body: some View {
        Group {
            if let data = code.pngData, let image = Image(pngData: data) {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.studioText3)
                    .padding(6)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension QRCode {
    var fileName: String {
        let base = Slug.suggestion(from: name)
        return (base.isEmpty ? "cardsite-qr-\(id)" : base) + ".png"
    }
}
