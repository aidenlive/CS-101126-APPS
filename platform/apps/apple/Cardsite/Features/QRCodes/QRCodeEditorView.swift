import SwiftUI
import StudioKit
import CardsiteKit

/// The QR builder, for a new code or an existing one: a native form beside
/// a live server preview.
///
/// - iPad and Mac (or any window 760 pt and wider): form and preview side
///   by side; the preview pane stays put while the form scrolls.
/// - iPhone: the preview is pinned above the form and folds into a compact
///   strip once the form scrolls.
///
/// Usable from anywhere that can present a sheet with `QRCodesModel` in the
/// environment, e.g. a link's "Create QR Code":
///
///     QRCodeEditorView(prefillURL: shortURL) { code in … }
struct QRCodeEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(QRCodesModel.self) private var codes

    private let mode: QRCodeBuilderModel.Mode
    private let onSaved: (QRCode) -> Void
    @State private var builder: QRCodeBuilderModel? = nil

    /// A new code. A `prefillURL` on the public short-link host starts as a
    /// dynamic code for that link; any other URL starts as a URL code.
    init(prefillURL: URL? = nil, onCreated: @escaping (QRCode) -> Void = { _ in }) {
        self.mode = .create(prefill: prefillURL)
        self.onSaved = onCreated
    }

    /// Edits an existing code, restoring every stored control.
    init(editing code: QRCode, onSaved: @escaping (QRCode) -> Void = { _ in }) {
        self.mode = .edit(code)
        self.onSaved = onSaved
    }

    var body: some View {
        Group {
            if let builder {
                QRCodeBuilderView(builder: builder, onSaved: onSaved)
            } else {
                Color.studioBg
            }
        }
        .onAppear {
            if builder == nil {
                builder = QRCodeBuilderModel(mode: mode, codes: codes, addresses: app.addresses)
            }
        }
        #if os(iOS)
        .presentationSizing(.page)
        #else
        .frame(minWidth: 720, idealWidth: 980, minHeight: 560, idealHeight: 760)
        #endif
    }
}

private struct QRCodeBuilderView: View {
    @Bindable var builder: QRCodeBuilderModel
    let onSaved: (QRCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWide = false
    @State private var isHeaderCollapsed = false
    @State private var confirmDiscard = false
    @State private var addressQuery = ""

    private static let wideThreshold: CGFloat = 760
    private static let previewPaneWidth: CGFloat = 380

    var body: some View {
        NavigationStack {
            content
                .background(Color.studioBg)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("qr.editor")
                .navigationTitle(builder.isEditing ? Text("Edit QR Code") : Text("New QR Code"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
                .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
        }
        .interactiveDismissDisabled(builder.hasChanges || builder.isSaving)
        .task { [builder] in await builder.load() }
        .task(id: builder.draft.payload) { [builder] in await builder.refreshPreview() }
        .task(id: builder.draft.type) { [builder] in await builder.loadLinksIfNeeded() }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        switch builder.phase {
        case .loading:
            loadingLayout
        case .failed(let error):
            ErrorStateView(error: error) { [builder] in await builder.load() }
        case .ready:
            Group {
                if isWide {
                    HStack(spacing: 0) {
                        form
                        Divider()
                        previewPane
                            .frame(width: Self.previewPaneWidth)
                    }
                } else {
                    VStack(spacing: 0) {
                        compactHeader
                        Divider()
                        form
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                geometry.contentOffset.y + geometry.contentInsets.top
                            } action: { _, offset in
                                updateHeader(forOffset: offset)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width >= Self.wideThreshold
            } action: { wide in
                isWide = wide
            }
        }
    }

    /// While an existing code loads: its stored image and a skeleton form.
    private var loadingLayout: some View {
        VStack(spacing: StudioSpace.s6) {
            QRArtwork(png: builder.preview.png, isLoading: true)
                .frame(maxWidth: StudioSpace.s16 * 3)
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                ForEach(0..<4, id: \.self) { _ in
                    QRSkeleton()
                        .frame(height: StudioSpace.s10)
                }
            }
            .frame(maxWidth: 560)
        }
        .padding(StudioSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading QR code"))
    }

    private func updateHeader(forOffset offset: CGFloat) {
        // Hysteresis, so a short form doesn't flicker at the threshold.
        let next: Bool
        if isHeaderCollapsed {
            next = offset > StudioSpace.s2
        } else {
            next = offset > StudioSpace.s10
        }
        guard next != isHeaderCollapsed else { return }
        withAnimation(reduceMotion ? nil : StudioAnimation.spring) {
            isHeaderCollapsed = next
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if builder.hasChanges { confirmDiscard = true } else { dismiss() }
            }
            .disabled(builder.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if builder.isSaving {
                ProgressView()
                    .accessibilityLabel(Text("Saving"))
            } else {
                Button {
                    Task { await save() }
                } label: {
                    builder.isEditing ? Text("Save") : Text("Create")
                }
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("qr.editor.save")
                .disabled(builder.phase != .ready)
            }
        }
    }

    private func save() async {
        guard let code = await builder.save() else { return }
        Haptics.success()
        onSaved(code)
        dismiss()
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                QRTextRow(label: String(localized: "Name"),
                          placeholder: String(localized: "My QR Code"),
                          help: String(localized: "Only you see this."),
                          text: $builder.draft.name,
                          error: builder.nameError)
                    .accessibilityIdentifier("qr.editor.name")
            }
            .listRowBackground(Color.studioSurface)

            Section {
                typeRow
            }
            .listRowBackground(Color.studioSurface)

            detailSections

            Section {
                colorRow(String(localized: "Foreground"), hex: $builder.draft.foreground, fallback: .studioText)
                colorRow(String(localized: "Background"), hex: $builder.draft.background, fallback: .studioSurface)
                transparencyRow
            } header: {
                Text("Colours")
            }
            .listRowBackground(Color.studioSurface)

            Section {
                Stepper(value: $builder.draft.size, in: QRCodeDraft.sizeRange, step: QRCodeDraft.sizeStep) {
                    LabeledContent("Size") {
                        Text("\(builder.draft.size) px").monospacedDigit()
                    }
                }
                Picker("Error Correction", selection: $builder.draft.errorLevel) {
                    ForEach(QRErrorLevel.allCases) { level in
                        Text(verbatim: level.rawValue)
                            .accessibilityLabel(Text(level.title))
                            .tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Output")
            } footer: {
                Text(QRErrorLevel(rawValue: builder.draft.errorLevel)?.explanation ?? "")
            }
            .listRowBackground(Color.studioSurface)

            if let error = builder.formError {
                Section {
                    FormErrorText(message: error)
                }
                .listRowBackground(Color.studioSurface)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var typeRow: some View {
        switch builder.types {
        case .loaded(let types) where !types.isEmpty:
            QRTypePicker(types: types, selection: builder.draft.type, label: builder.typeLabel) { type in
                withAnimation(reduceMotion ? nil : StudioAnimation.base) {
                    builder.selectType(type)
                }
            }
        case .failed, .loaded:
            LabeledContent("Type", value: builder.typeLabel)
            Button("Couldn't load the other types. Try Again") {
                Task { [builder] in await builder.retryTypes() }
            }
        case .idle, .loading:
            LabeledContent("Type") {
                HStack(spacing: StudioSpace.s2) {
                    Text(builder.typeLabel)
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var detailSections: some View {
        let detailsTitle = String(localized: "\(builder.typeLabel) Details")
        if builder.draft.type == QRCodeCatalog.dynamicURLType {
            Section {
                linkPicker
            } header: {
                Text(detailsTitle)
            } footer: {
                Text("Change the link's destination any time; printed codes follow it.")
            }
            .listRowBackground(Color.studioSurface)
        } else {
            let groups = QRCodeCatalog.groups(for: builder.draft.type)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    ForEach(group.fields) { field in
                        QRFieldRow(field: field, draft: $builder.draft)
                            .accessibilityIdentifier("qr.editor.\(field.key)")
                    }
                } header: {
                    Text(group.title ?? detailsTitle)
                } footer: {
                    if index == groups.count - 1, let footer = detailsFooter {
                        Text(footer)
                    }
                }
                .listRowBackground(Color.studioSurface)
            }
            if builder.draft.type == "location" {
                Section {
                    addressFinder
                } header: {
                    Text("Find by Address")
                } footer: {
                    Text("Fills in the coordinates. The code encodes the coordinates, not the address.")
                }
                .listRowBackground(Color.studioSurface)
            }
        }
    }

    private var detailsFooter: String? {
        switch builder.draft.type {
        case "event":
            return String(localized: "Times are the event's local time and read the same in every time zone.")
        case "url":
            return String(localized: "Fixed once printed. To change it later, use a Dynamic URL instead.")
        default:
            return nil
        }
    }

    @ViewBuilder
    private var linkPicker: some View {
        switch builder.links {
        case .idle, .loading:
            LabeledContent("Link") {
                ProgressView().controlSize(.small)
            }
        case .failed(let error):
            Text(error.localizedDescription)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
            Button("Try Again") {
                Task { [builder] in await builder.retryLinks() }
            }
        case .loaded(let items) where items.isEmpty && builder.unmatchedDynamicURL == nil:
            StudioBanner(lead: String(localized: "No links yet."),
                         message: String(localized: "Create a short link first, or choose the URL type to encode any web address."),
                         tone: .info)
        case .loaded(let items):
            Picker("Link", selection: $builder.selectedLinkID) {
                if let url = builder.unmatchedDynamicURL {
                    Text(verbatim: url).tag(Int?.none)
                } else {
                    Text("Choose a link").tag(Int?.none)
                }
                ForEach(items) { link in
                    Text(verbatim: builder.displayAddress(for: link)).tag(Int?.some(link.id))
                }
            }
            if let error = builder.linkError {
                FormErrorText(message: error)
            }
        }
    }

    @ViewBuilder
    private var addressFinder: some View {
        QRTextRow(label: String(localized: "Address"),
                  placeholder: String(localized: "1 Infinite Loop, Cupertino"),
                  text: $addressQuery,
                  error: builder.geocodeError)
            .onSubmit { find() }
        Button {
            find()
        } label: {
            HStack(spacing: StudioSpace.s2) {
                if builder.isGeocoding {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "location.magnifyingglass")
                }
                Text("Find Coordinates")
            }
        }
        .disabled(addressQuery.trimmingCharacters(in: .whitespaces).isEmpty || builder.isGeocoding)
    }

    private func find() {
        let query = addressQuery
        Task { [builder] in await builder.findCoordinates(for: query) }
    }

    private func colorRow(_ title: String, hex: Binding<String>, fallback: Color) -> some View {
        ColorPicker(selection: HexColor.binding(hex, fallback: fallback), supportsOpacity: false) {
            HStack(spacing: StudioSpace.s2) {
                Text(title)
                Spacer(minLength: StudioSpace.s2)
                Text(verbatim: hex.wrappedValue.uppercased())
                    .studioText(.mono)
                    .foregroundStyle(Color.studioText3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(Text(verbatim: hex.wrappedValue.uppercased()))
    }

    private var transparencyRow: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            LabeledContent("Background Transparency") {
                Text("\(builder.draft.transparency)%").monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(builder.draft.transparency) },
                    set: { builder.draft.transparency = Int($0.rounded()) }
                ),
                in: 0...100,
                step: 1
            ) {
                Text("Background Transparency")
            }
            .accessibilityValue(Text("\(builder.draft.transparency) percent"))
        }
    }

    // MARK: Preview

    private var artwork: some View {
        QRArtwork(
            png: builder.preview.png,
            isTransparent: builder.draft.transparency > 0,
            isLoading: builder.preview.isLoading,
            isEmpty: !builder.draft.hasContent
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("QR code preview"))
        .accessibilityValue(previewAccessibilityValue)
    }

    private var previewAccessibilityValue: Text {
        if !builder.draft.hasContent { return Text("Nothing to encode yet") }
        if builder.preview.isLoading { return Text("Updating") }
        if let data = builder.preview.embeddedData { return Text(verbatim: data) }
        return Text("")
    }

    private var displayName: String {
        builder.draft.trimmedName.isEmpty ? String(localized: "Untitled") : builder.draft.trimmedName
    }

    /// iPad and Mac: the preview on a Studio card with generous margins, the
    /// name underneath in the display face.
    private var previewPane: some View {
        ScrollView {
            VStack(spacing: StudioSpace.s5) {
                StudioCard(radius: StudioRadius.xl) {
                    artwork
                        .padding(StudioSpace.s4)
                }

                VStack(spacing: StudioSpace.s2) {
                    Text(displayName)
                        .studioText(.title)
                        .foregroundStyle(builder.draft.trimmedName.isEmpty ? Color.studioText4 : Color.studioText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    HStack(spacing: StudioSpace.s2) {
                        StudioStatusPill(builder.typeLabel)
                        Text("\(builder.draft.size) × \(builder.draft.size) px")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)

                previewStatus
                previewActions
            }
            .padding(StudioSpace.s6)
        }
        .background(Color.studioBg)
    }

    /// iPhone: the preview pinned above the form, folding to a strip.
    private var compactHeader: some View {
        Group {
            if isHeaderCollapsed {
                HStack(spacing: StudioSpace.s3) {
                    artwork
                        .padding(StudioSpace.s1)
                        .background(Color.studioSurface, in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
                        .frame(width: StudioSpace.s16)
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text(displayName)
                            .studioText(.ui)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.studioText)
                            .lineLimit(1)
                        compactStatusLine
                    }
                    Spacer(minLength: StudioSpace.s2)
                    shareButton(iconOnly: true)
                }
                .padding(.horizontal, StudioSpace.s5)
                .padding(.vertical, StudioSpace.s3)
            } else {
                VStack(spacing: StudioSpace.s3) {
                    artwork
                        .padding(StudioSpace.s4)
                        .background(Color.studioSurface, in: RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous)
                                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
                        )
                        .frame(maxWidth: StudioSpace.s16 * 3)
                    Text(displayName)
                        .studioText(.titleSm)
                        .foregroundStyle(builder.draft.trimmedName.isEmpty ? Color.studioText4 : Color.studioText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    compactStatusLine
                }
                .padding(.horizontal, StudioSpace.s5)
                .padding(.vertical, StudioSpace.s4)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.studioBg)
    }

    @ViewBuilder
    private var compactStatusLine: some View {
        if let error = builder.preview.error {
            Button {
                Task { [builder] in await builder.retryPreview() }
            } label: {
                Label(error.localizedDescription, systemImage: "exclamationmark.circle.fill")
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
            .studioText(.uiSm)
            .foregroundStyle(Color.studioError)
            .accessibilityHint(Text("Tries the preview again"))
        } else {
            Text(statusText)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .lineLimit(2)
        }
    }

    private var statusText: String {
        if !builder.draft.hasContent { return String(localized: "Fill in the details to see your code.") }
        if builder.preview.isLoading { return String(localized: "Updating preview…") }
        return String(localized: "Saved exactly as previewed.")
    }

    @ViewBuilder
    private var previewStatus: some View {
        if let error = builder.preview.error {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                StudioBanner(lead: String(localized: "Couldn't preview."),
                             message: error.localizedDescription,
                             tone: error == .offline ? .warning : .error)
                StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline,
                             isLoading: builder.preview.isLoading) {
                    Task { [builder] in await builder.retryPreview() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(statusText)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var previewActions: some View {
        if let png = builder.preview.png, !builder.preview.isLoading, builder.draft.hasContent {
            QRExportActions(png: png,
                            fileName: builder.fileName,
                            title: displayName,
                            copyText: builder.preview.embeddedData,
                            copyTitle: QRCodeCatalog.encodesURL(builder.draft.type)
                                ? String(localized: "Copy Link") : String(localized: "Copy Content"))
        }
    }

    @ViewBuilder
    private func shareButton(iconOnly: Bool) -> some View {
        if let png = builder.preview.png, !builder.preview.isLoading, builder.draft.hasContent {
            ShareLink(item: PNGFile(data: png, name: builder.fileName),
                      preview: SharePreview(displayName, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
                Label("Share Image", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(Text("Share Image"))
        }
    }
}

/// L / M / Q / H, worded as on the web.
enum QRErrorLevel: String, CaseIterable, Identifiable {
    case low = "L", medium = "M", quartile = "Q", high = "H"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return String(localized: "Low (7%)")
        case .medium: return String(localized: "Medium (15%)")
        case .quartile: return String(localized: "Quartile (25%)")
        case .high: return String(localized: "High (30%)")
        }
    }

    var explanation: String {
        switch self {
        case .low: return String(localized: "Low (7%): the smallest code; best on screens and clean prints.")
        case .medium: return String(localized: "Medium (15%): still scans with up to 15% of it damaged or covered.")
        case .quartile: return String(localized: "Quartile (25%): for print that may get scuffed.")
        case .high: return String(localized: "High (30%): the most robust, and the densest.")
        }
    }
}

#Preview("New code") {
    QRCodeEditorView()
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model())
}

#Preview("Prefilled link") {
    QRCodeEditorView(prefillURL: URL(string: "https://card.site/menu"))
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model())
}
