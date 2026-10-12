import SwiftUI
import StudioKit
import CardsiteKit

/// QR codes as an adaptive grid of cards: two columns on iPhone, as many as
/// fit on iPad and Mac. A card opens the code; its menu edits, shares or
/// deletes it.
struct QRCodesScreen: View {
    @Environment(QRCodesModel.self) private var model
    @State private var path: [QRCode.ID] = []
    @State private var isComposing = false
    @State private var editing: QRCode? = nil
    @State private var pendingDelete: QRCode? = nil
    @State private var deleteError: String? = nil
    @State private var hoveredID: QRCode.ID? = nil
    @Environment(\.studioViewport) private var viewport
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// The narrowest card, scaled with the text so titles keep their room.
    @ScaledMetric(relativeTo: .body) private var cardMin: CGFloat = StudioSpace.s16 * 2 + StudioSpace.s6
    @ScaledMetric(relativeTo: .body) private var cardMax: CGFloat = StudioSpace.s16 * 4

    var body: some View {
        @Bindable var bindable = model
        NavigationStack(path: $path) {
            content
                .background(Color.studioBg)
                .navigationTitle("QR Codes")
                .searchable(text: $bindable.searchText, prompt: Text("Search QR codes"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { isComposing = true } label: {
                            Label("New QR Code", systemImage: "plus")
                        }
                        .accessibilityIdentifier("qr.create")
                    }
                }
                .navigationDestination(for: QRCode.ID.self) { id in
                    if let code = model.list.items.first(where: { $0.id == id }) {
                        QRCodeDetailView(code: code,
                                         typeLabel: model.typeLabel(for: code.type),
                                         edit: { editing = code },
                                         requestDelete: { pendingDelete = code })
                    } else {
                        ContentUnavailableView("This QR code was deleted", systemImage: "qrcode")
                    }
                }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .task { [model] in await model.loadTypesIfNeeded() }
        .sheet(isPresented: $isComposing) {
            QRCodeEditorView { code in path = [code.id] }
        }
        .sheet(item: $editing) { code in
            QRCodeEditorView(editing: code)
        }
        .confirmationDialog(
            "Delete this QR code?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { code in
            Button("Delete", role: .destructive) {
                Task { await delete(code) }
            }
        } message: { _ in
            Text("This removes it from your workspace. Printed copies keep encoding the same content.")
        }
        .alert(String(localized: "Couldn’t delete"), isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch model.list.state {
        case .idle, .loading:
            ScrollView {
                grid {
                    ForEach(QRCode.skeletons) { code in
                        QRCodeCard(code: code, typeLabel: QRCodeCatalog.fallbackLabel(code.type))
                    }
                }
                .padding(.horizontal, viewport.contentPadding)
                .padding(.vertical, StudioSpace.s5)
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading QR codes"))
        case .failed(let error):
            ErrorStateView(error: error) { [list = model.list] in await list.refresh() }
        case .loaded(let items) where items.isEmpty:
            ScrollView {
                StudioEmptyState(
                    systemImage: "qrcode",
                    title: String(localized: "No QR codes yet"),
                    message: String(localized: "Make a code for a web address, a WiFi network, a contact card, an event or a payment. Point one at a short link and you can change where it goes after it’s printed.")
                ) {
                    StudioButton(String(localized: "New QR Code"), systemImage: "plus", variant: .primary) {
                        isComposing = true
                    }
                }
                .padding(StudioSpace.s6)
                .readableWidth(.sheet)
            }
            .refreshable { [list = model.list] in await list.refresh() }
        case .loaded:
            codeGrid
        }
    }

    private var codeGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                }
                if model.visibleCodes.isEmpty, !model.searchText.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, StudioSpace.s10)
                }
                grid {
                    ForEach(model.visibleCodes) { code in
                        card(for: code)
                    }
                }
                if model.list.hasMore, model.searchText.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(StudioSpace.s4)
                        .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
                }
            }
            .padding(.horizontal, viewport.contentPadding)
            .padding(.vertical, StudioSpace.s5)
        }
        .refreshable { [list = model.list] in await list.refresh() }
    }

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(
            // At accessibility sizes the cards take the full width they're given.
            columns: [dynamicTypeSize.isAccessibilitySize
                      ? GridItem(.adaptive(minimum: cardMin), spacing: StudioSpace.s4, alignment: .top)
                      : GridItem(.adaptive(minimum: cardMin, maximum: cardMax), spacing: StudioSpace.s4, alignment: .top)],
            alignment: .leading,
            spacing: StudioSpace.s4,
            content: content
        )
    }

    private func card(for code: QRCode) -> some View {
        NavigationLink(value: code.id) {
            QRCodeCard(code: code, typeLabel: model.typeLabel(for: code.type))
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityIdentifier("qr.row.\(code.id)")
        .overlay(alignment: .topTrailing) {
            if showsMenuButton(for: code) {
                Menu {
                    menuItems(for: code)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.studioText2)
                        .frame(width: StudioSpace.s8, height: StudioSpace.s8)
                        .background(Color.studioSurface, in: Circle())
                        .overlay(Circle().strokeBorder(Color.studioBorder, lineWidth: 0.5))
                        // The full 44pt target around the small disc.
                        .frame(minWidth: StudioLayout.tapTarget, minHeight: StudioLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel(Text("Actions for \(code.name)"))
                .transition(.opacity)
            }
        }
        .onHover { isHovering in
            withAnimation(StudioAnimation.base) { hoveredID = isHovering ? code.id : (hoveredID == code.id ? nil : hoveredID) }
        }
        .contextMenu { menuItems(for: code) }
    }

    /// The card's own menu button: on hover on the Mac, always on a regular
    /// iPad. On iPhone the context menu (long press) carries the same items,
    /// and the button would sit over the artwork.
    private func showsMenuButton(for code: QRCode) -> Bool {
        #if os(macOS)
        return hoveredID == code.id
        #elseif os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    @ViewBuilder
    private func menuItems(for code: QRCode) -> some View {
        Button { editing = code } label: {
            Label("Edit…", systemImage: "pencil")
        }
        if let png = code.pngData {
            ShareLink(item: PNGFile(data: png, name: code.fileName),
                      preview: SharePreview(code.name, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
                Label("Share Image…", systemImage: "square.and.arrow.up")
            }
        }
        if let target = code.target, !target.isEmpty {
            Button {
                Pasteboard.copy(target)
                Haptics.success()
            } label: {
                Label(code.copyTitle, systemImage: "doc.on.doc")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = code } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    private func delete(_ code: QRCode) async {
        do {
            try await model.delete(code)
            path.removeAll { $0 == code.id }
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

/// One code in the grid: the image on a quiet surface, then name, type and
/// date. The menu button sits over the top-right corner, outside this view.
struct QRCodeCard: View {
    let code: QRCode
    let typeLabel: String

    var body: some View {
        StudioCard(flush: true, hover: true) {
            VStack(alignment: .leading, spacing: 0) {
                QRImage(code: code)
                    .padding(StudioSpace.s5)
                    .frame(maxWidth: .infinity)
                    .background(Color.studioSurface2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: StudioSpace.s2) {
                    Text(code.name)
                        .studioText(.ui)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: StudioSpace.s2) {
                        Image(systemName: QRCodeCatalog.symbol(for: code.type))
                            .font(.caption)
                            .foregroundStyle(Color.studioText3)
                            .accessibilityHidden(true)
                        Text(typeLabel)
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                    if let created = code.createdAt {
                        Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .padding(StudioSpace.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(code.name), \(typeLabel)"))
    }
}

private extension QRCode {
    /// Stand-ins drawn redacted while the first page loads.
    static let skeletons: [QRCode] = (1...6).map {
        QRCode(id: -$0, name: "QR code name", type: "url", imageDataURL: nil, embeddedData: nil, createdAt: Date.now)
    }
}

#Preview("QR codes") {
    QRCodesScreen()
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model())
}

#Preview("Empty") {
    QRCodesScreen()
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model(codes: []))
}

#Preview("Offline") {
    QRCodesScreen()
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model(failing: .offline))
}
