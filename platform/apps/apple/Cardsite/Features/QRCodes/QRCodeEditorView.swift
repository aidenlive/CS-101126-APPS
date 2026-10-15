import SwiftUI
import StudioKit
import CardsiteKit

/// The QR builder, for a new code or an existing one, laid out like the
/// Photos editor: a stage with the live server preview, and the controls in
/// three groups (Content · Style · Output).
///
/// - iPad and Mac (any window 680 pt and wider, below accessibility text
///   sizes): the stage on the leading side, sticky; the switcher at the top
///   of the controls column beside it.
/// - iPhone: the stage on top, folding into a compact strip as the controls
///   scroll; the switcher is a wide glass pill in the bottom bar.
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
        .cardsiteSheet(.page)
        #if os(iOS)
        // Studio detail sheet: full height, with the grabber.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

/// The builder's three groups of controls.
enum QRBuilderSection: String, CaseIterable, Identifiable {
    case content, style, output

    var id: Self { self }

    var title: String {
        switch self {
        case .content: return String(localized: "Content")
        case .style: return String(localized: "Style")
        case .output: return String(localized: "Output")
        }
    }
}

private struct QRCodeBuilderView: View {
    @Bindable var builder: QRCodeBuilderModel
    let onSaved: (QRCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0
    @State private var section: QRBuilderSection = .content
    @State private var isHeaderCollapsed = false
    @State private var confirmDiscard = false
    @State private var addressQuery = ""
    @State private var isExporting = false
    @State private var exportError: String? = nil

    private static let wideThreshold: CGFloat = 680

    /// Side by side only when there is room and the text isn't at an
    /// accessibility size; otherwise the stage stacks above the controls.
    private var isWide: Bool {
        width >= Self.wideThreshold && !dynamicTypeSize.isAccessibilitySize
    }

    /// The stage column: about two fifths of the window, within bounds.
    private var stageWidth: CGFloat {
        min(max(width * 0.42, StudioSpace.s16 * 5 + StudioSpace.s5), StudioSpace.s16 * 8)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    width = newWidth
                }
                .background(Color.studioBg)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("qr.editor")
                .navigationTitle(builder.isEditing ? Text("Edit QR Code") : Text("New QR Code"))
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
                .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
                .qrImageExporter(isPresented: $isExporting, png: builder.preview.png,
                                 fileName: builder.fileName, error: $exportError)
                .alert(String(localized: "Couldn’t save the image"),
                       isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(exportError ?? "")
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
            if isWide {
                wideLayout
            } else {
                compactLayout
            }
        }
    }

    /// iPad and Mac: the stage sticky on the leading side, the controls
    /// beside it with the switcher on top.
    private var wideLayout: some View {
        HStack(spacing: 0) {
            stageColumn
                .frame(width: stageWidth)
            Divider()
            VStack(spacing: 0) {
                sectionPicker
                    .frame(maxWidth: CardsiteMeasure.sheet.width)
                    .padding(.horizontal, StudioSpace.s5)
                    .padding(.vertical, StudioSpace.s3)
                    .frame(maxWidth: .infinity)
                Divider()
                controls
            }
        }
    }

    /// The stage centred in its column while it fits; scrolls in a short
    /// window instead of clipping.
    private var stageColumn: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Spacer(minLength: StudioSpace.s8)
                stage(.regular)
                Spacer(minLength: StudioSpace.s8)
            }
            .padding(.horizontal, StudioSpace.s8)
            ScrollView {
                stage(.regular)
                    .padding(StudioSpace.s8)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.studioCanvasBg)
    }

    /// iPhone (and accessibility sizes): the stage above the controls, the
    /// switcher in the bottom bar.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            compactHeader
            Divider()
            controls
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    updateHeader(forOffset: offset)
                }
                .edgeBar(.bottom) { bottomBar }
        }
    }

    /// While an existing code loads: its stored image on the stage and a
    /// skeleton of the controls.
    private var loadingLayout: some View {
        VStack(spacing: 0) {
            QRStage(png: builder.preview.png,
                    isLoading: true,
                    title: loadingCode?.name ?? "",
                    typeLabel: QRCodeCatalog.fallbackLabel(loadingCode?.type ?? builder.draft.type),
                    typeSymbol: QRCodeCatalog.symbol(for: loadingCode?.type ?? builder.draft.type),
                    scale: isWide ? .regular : .compact,
                    accessibilityLabel: Text("QR code preview"))
                .padding(StudioSpace.s6)
                .frame(maxWidth: .infinity)
                .background(Color.studioCanvasBg)
            Divider()
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                ForEach(0..<4, id: \.self) { _ in
                    QRSkeleton()
                        .frame(height: StudioSpace.s10)
                }
            }
            .padding(StudioSpace.s6)
            .frame(maxWidth: CardsiteMeasure.sheet.width)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading QR code"))
    }

    private var loadingCode: QRCode? {
        if case .edit(let code) = builder.mode { return code }
        return nil
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

    // MARK: Switcher

    private var sectionPicker: some View {
        Picker(selection: $section) {
            ForEach(QRBuilderSection.allCases) { item in
                Text(item.title).tag(item)
            }
        } label: {
            Text("Builder Controls")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("qr.editor.section")
    }

    /// iPhone: the switcher as a wide floating pill. The glass is chrome over
    /// the controls, never over the code; StudioKit makes it opaque under
    /// Reduce Transparency.
    private var bottomBar: some View {
        sectionPicker
            .controlSize(.large)
            .padding(StudioSpace.s1)
            .studioGlass(cornerRadius: StudioRadius.pill)
            .frame(maxWidth: CardsiteMeasure.narrow.width)
            .padding(.horizontal, StudioSpace.s5)
            .padding(.vertical, StudioSpace.s2)
            .frame(maxWidth: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                if builder.hasChanges { confirmDiscard = true } else { dismiss() }
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .labelStyle(QRToolbarLabelStyle())
            .keyboardShortcut(.cancelAction)
            .disabled(builder.isSaving)
        }
        if builder.isEditing {
            ToolbarItemGroup(placement: .primaryAction) {
                shareButton
                Button {
                    isExporting = true
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }
                .disabled(exportablePNG == nil)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if builder.isSaving {
                ProgressView()
                    .accessibilityLabel(Text("Saving"))
            } else {
                Button {
                    Task { await save() }
                } label: {
                    Label {
                        builder.isEditing ? Text("Save") : Text("Create")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                }
                .labelStyle(QRToolbarLabelStyle())
                .modifier(QRConfirmButtonStyle())
                .tint(Color.studioAccentLine)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("qr.editor.save")
                .disabled(builder.phase != .ready)
            }
        }
    }

    /// The preview image, once it shows what the draft encodes.
    private var exportablePNG: Data? {
        guard let png = builder.preview.png, !builder.preview.isLoading, builder.draft.hasContent else { return nil }
        return png
    }

    @ViewBuilder
    private var shareButton: some View {
        if let png = exportablePNG {
            ShareLink(item: PNGFile(data: png, name: builder.fileName),
                      preview: SharePreview(displayName, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
                Label("Share Image", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {} label: {
                Label("Share Image", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
        }
    }

    private func save() async {
        guard let code = await builder.save() else {
            // Show the field that needs attention.
            if builder.nameError != nil || builder.linkError != nil || !builder.draft.hasContent {
                section = .content
            }
            return
        }
        Haptics.success()
        onSaved(code)
        dismiss()
    }

    // MARK: Controls

    private var controls: some View {
        Form {
            switch section {
            case .content: contentSections
            case .style: styleSections
            case .output: outputSections
            }

            if let error = builder.formError {
                Section {
                    FormErrorText(message: error)
                }
                .studioRowBackground()
            }
        }
        .studioForm(measure: .sheet)
        .dismissesKeyboardOnScroll()
        .disabled(builder.isSaving)
    }

    // MARK: Content

    @ViewBuilder
    private var contentSections: some View {
        Section {
            QRTextRow(label: String(localized: "Name"),
                      placeholder: String(localized: "My QR Code"),
                      help: String(localized: "Only you see this."),
                      text: $builder.draft.name,
                      error: builder.nameError)
                .accessibilityIdentifier("qr.editor.name")
        }
        .studioRowBackground()

        Section {
            typeRow
        }
        .studioRowBackground()

        detailSections
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
            FormRetryRow(message: String(localized: "Couldn’t load the other types.")) { [builder] in
                await builder.retryTypes()
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
                Text("Change the link’s destination any time; printed codes follow it.")
            }
            .studioRowBackground()
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
                .studioRowBackground()
            }
            if builder.draft.type == "location" {
                Section {
                    addressFinder
                } header: {
                    Text("Find by Address")
                } footer: {
                    Text("Fills in the coordinates. The code encodes the coordinates, not the address.")
                }
                .studioRowBackground()
            }
        }
    }

    private var detailsFooter: String? {
        switch builder.draft.type {
        case "event":
            return String(localized: "Times are the event’s local time and read the same in every time zone.")
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

    // MARK: Style

    @ViewBuilder
    private var styleSections: some View {
        Section {
            QRPresetRow(draft: $builder.draft)
        } header: {
            Text("Presets")
        }
        .studioRowBackground()

        Section {
            QRSwatchRow(title: String(localized: "Foreground"), hex: $builder.draft.foreground, fallback: .studioText)
            QRSwatchRow(title: String(localized: "Background"), hex: $builder.draft.background, fallback: .studioSurface)
            Button {
                let foreground = builder.draft.foreground
                builder.draft.foreground = builder.draft.background
                builder.draft.background = foreground
            } label: {
                Label("Swap Colors", systemImage: "arrow.up.arrow.down")
            }
            if let note = QRContrastNote.message(for: builder.draft) {
                QRContrastNote(message: note)
            }
        } header: {
            Text("Colors")
        }
        .studioRowBackground()

        Section {
            transparencyRow
        } header: {
            Text("Transparency")
        } footer: {
            Text("A transparent background takes the color of whatever the code is printed on. The stage shows it as a checkerboard.")
        }
        .studioRowBackground()
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

    // MARK: Output

    @ViewBuilder
    private var outputSections: some View {
        Section {
            Stepper(value: $builder.draft.size, in: QRCodeDraft.sizeRange, step: QRCodeDraft.sizeStep) {
                LabeledContent("Size") {
                    Text("\(builder.draft.size) × \(builder.draft.size) px").monospacedDigit()
                }
            }
        } header: {
            Text("Image")
        } footer: {
            Text("The width and height of the saved PNG.")
        }
        .studioRowBackground()

        Section {
            Picker("Error Correction", selection: $builder.draft.errorLevel) {
                ForEach(QRErrorLevel.allCases) { level in
                    Text(verbatim: level.rawValue)
                        .accessibilityLabel(Text(level.title))
                        .tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Error Correction")
        } footer: {
            Text(QRErrorLevel(rawValue: builder.draft.errorLevel)?.explanation ?? "")
        }
        .studioRowBackground()
    }

    // MARK: Stage

    private func stage(_ scale: QRStageScale) -> some View {
        QRStage(
            png: builder.preview.png,
            isTransparent: builder.draft.transparency > 0,
            isLoading: builder.preview.isLoading,
            isEmpty: !builder.draft.hasContent,
            title: displayName,
            isTitlePlaceholder: builder.draft.trimmedName.isEmpty,
            typeLabel: builder.typeLabel,
            typeSymbol: QRCodeCatalog.symbol(for: builder.draft.type),
            scale: scale,
            accessibilityLabel: Text("QR code preview"),
            accessibilityValue: previewAccessibilityValue
        ) {
            if scale == .compact {
                compactStatusLine
            } else {
                previewStatus
            }
        }
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

    /// iPhone: the stage pinned above the controls, folding to a strip once
    /// they scroll. At accessibility sizes it stays a strip, so the controls
    /// keep the room.
    private var compactHeader: some View {
        Group {
            if isHeaderCollapsed || dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: StudioSpace.s3) {
                    QRPaper(padding: StudioSpace.s1, radius: StudioRadius.sm, elevated: false) {
                        QRArtwork(png: builder.preview.png,
                                  isTransparent: builder.draft.transparency > 0,
                                  isLoading: builder.preview.isLoading,
                                  isEmpty: !builder.draft.hasContent)
                    }
                    .frame(width: StudioSpace.s16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("QR code preview"))
                    .accessibilityValue(previewAccessibilityValue)
                    .accessibilityAddTraits(.isImage)
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text(displayName)
                            .studioText(.ui)
                            .fontWeight(.semibold)
                            .foregroundStyle(builder.draft.trimmedName.isEmpty ? Color.studioText4 : Color.studioText)
                            .lineLimit(2)
                        compactStatusLine
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, StudioSpace.s5)
                .padding(.vertical, StudioSpace.s3)
            } else {
                stage(.compact)
                    .padding(.horizontal, StudioSpace.s5)
                    .padding(.top, StudioSpace.s5)
                    .padding(.bottom, StudioSpace.s4)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.studioCanvasBg)
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

    /// iPad and Mac: the size, then the status or the preview error.
    private var previewStatus: some View {
        VStack(spacing: StudioSpace.s3) {
            Text("\(builder.draft.size) × \(builder.draft.size) px")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .monospacedDigit()
            if let error = builder.preview.error {
                VStack(alignment: .leading, spacing: StudioSpace.s3) {
                    StudioBanner(lead: String(localized: "Couldn’t preview."),
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
            }
        }
        .padding(.top, StudioSpace.s1)
    }
}

// MARK: - Toolbar styling

/// ✕ and ✓ as symbols on iOS 26, where the system draws them as round glass
/// buttons; the words below 26 and on the Mac, where a text button is the
/// convention. VoiceOver reads the title either way.
private struct QRToolbarLabelStyle: LabelStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            configuration.icon
        } else {
            configuration.title
        }
        #else
        configuration.title
        #endif
    }
}

/// The one prominent action: `.glassProminent` on 26, the system's own
/// confirmation style before it.
private struct QRConfirmButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content
        }
        #endif
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

#Preview("Editing") {
    QRCodeEditorView(editing: QRCodesPreviewData.codes[1])
        .environment(QRCodesPreviewData.app)
        .environment(QRCodesPreviewData.model())
}
