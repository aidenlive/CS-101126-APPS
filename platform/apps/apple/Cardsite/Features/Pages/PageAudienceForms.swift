import SwiftUI
import StudioKit
import CardsiteKit

// MARK: - Display rules

/// Audience targeting for the page: six dimensions from the server's own
/// vocabulary (`GET /reference/targeting`), written to `display_rules`.
///
/// A local, simple version of the web's DisplayRulesEditor. The web also
/// shows a scheduling toggle that writes `display_rules.scheduled_*`, which
/// no server code reads for bio pages, so it is left out here.
/// Replace this with the shared `Features/ResourceEditor/DisplayRulesSection`
/// once that lands.
struct DisplayRulesForm: View {
    @Environment(PagesModel.self) private var pages
    let editor: PageEditorModel

    @State private var options: Loadable<TargetingOptions> = .idle
    @State private var editing: DisplayRules.Dimension?
    @State private var isSaving = false
    @State private var saveError: String?

    private var rules: DisplayRules { DisplayRules(json: editor.page?.displayRules ?? [:]) }

    /// Without the capability, rules can be cleared but not added (the
    /// server's rule: setting targeting takes the gate, clearing never does).
    private var isLocked: Bool {
        !pages.allows(PagesModel.Capability.targeting) && !rules.narrowsAudience
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: StudioSpace.s2) {
                    Text("Audience targeting")
                        .studioText(.ui)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.studioText)
                    if rules.narrowsAudience {
                        StudioStatusPill(String(localized: "Active"), tone: .success)
                    }
                }
                Text("Show this page only to visitors who match every rule. Leave a rule empty to allow everyone.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
                if isLocked {
                    Text("Audience targeting isn't included in your plan, so these rules can't be set.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .failed = options {
                Section {
                    StudioBanner(
                        lead: String(localized: "Targeting options didn't load."),
                        message: String(localized: "The pickers are unavailable. Any rules already set are kept and saved unchanged."),
                        tone: .warning
                    )
                    Button("Try Again") { Task { await load() } }
                }
            }
            Section {
                ForEach(DisplayRules.Dimension.allCases) { dimension in
                    EditorValueRow(
                        label: Self.title(dimension),
                        value: summary(for: dimension),
                        isDisabled: isLocked || options.value == nil || isSaving
                    ) {
                        editing = dimension
                    }
                }
            } footer: {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle.fill")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioError)
                } else if isSaving {
                    Text("Saving…")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
        }
        .task { if options.value == nil { await load() } }
        .sheet(item: $editing) { dimension in
            OptionPickerSheet(
                title: Self.title(dimension),
                options: (options.value?.options(for: dimension) ?? []).map { PickerOption(value: $0.value, label: $0.label) },
                selected: rules[dimension],
                allowsMultiple: true
            ) { chosen in
                Task { await save(dimension, chosen) }
            }
        }
    }

    static func title(_ dimension: DisplayRules.Dimension) -> String {
        switch dimension {
        case .countries: return String(localized: "Countries")
        case .continents: return String(localized: "Continents")
        case .browsers: return String(localized: "Browsers")
        case .operatingSystems: return String(localized: "Operating systems")
        case .deviceTypes: return String(localized: "Devices")
        case .languages: return String(localized: "Languages")
        }
    }

    static func everyone(_ dimension: DisplayRules.Dimension) -> String {
        switch dimension {
        case .countries: return String(localized: "All countries")
        case .continents: return String(localized: "All continents")
        case .browsers: return String(localized: "All browsers")
        case .operatingSystems: return String(localized: "All operating systems")
        case .deviceTypes: return String(localized: "All devices")
        case .languages: return String(localized: "All languages")
        }
    }

    private func summary(for dimension: DisplayRules.Dimension) -> String {
        let values = rules[dimension]
        guard !values.isEmpty else { return Self.everyone(dimension) }
        // A stored value with no label (vocabulary not loaded, or retired)
        // shows as stored rather than disappearing.
        let vocabulary = options.value?.options(for: dimension) ?? []
        let labels = values.map { value in vocabulary.first { $0.value == value }?.label ?? value }
        if labels.count <= 2 { return labels.joined(separator: ", ") }
        return String(localized: "\(labels[0]), \(labels[1]) and \(labels.count - 2) more")
    }

    private func load() async {
        options = .loading
        do {
            options = .loaded(try await pages.client.targetingOptions())
        } catch is CancellationError {
            options = .idle
        } catch {
            options = .failed(error.asAPIError)
        }
    }

    private func save(_ dimension: DisplayRules.Dimension, _ chosen: [String]) async {
        var updated = rules
        updated[dimension] = chosen
        isSaving = true
        defer { isSaving = false }
        do {
            // The whole object goes back: other keys (`cities`, conditions)
            // ride along in `DisplayRules.other`.
            try await editor.savePage(BioPageChanges(displayRules: updated.json))
            saveError = nil
        } catch {
            saveError = error.asAPIError.localizedDescription
        }
    }
}

// MARK: - Pixels

/// The workspace's pixels, attached to this page or not. The order the
/// author attaches them in is the order stored.
struct PixelsForm: View {
    @Environment(PagesModel.self) private var pages
    let editor: PageEditorModel

    @State private var pixels: Loadable<[BioPixel]> = .idle
    @State private var types: [String: BioPixelType] = [:]
    @State private var savingID: BioPixel.ID?
    @State private var saveError: String?

    private var attached: [Int] { editor.page?.pixelIDs ?? [] }

    var body: some View {
        Form {
            Section {
                Text("Pixels emit on your public page as the provider's own no-script beacon. Providers without one can't emit here, and are marked.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch pixels {
            case .idle, .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView().accessibilityLabel("Loading pixels")
                        Spacer()
                    }
                }
            case .failed(let error):
                Section {
                    StudioBanner(lead: String(localized: "Pixels didn't load."), message: error.localizedDescription, tone: .warning)
                    Button("Try Again") { Task { await load() } }
                }
            case .loaded(let list) where list.isEmpty:
                Section {
                    Text("No pixels yet. Create one under Pixels to attach it here.")
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText2)
                }
            case .loaded(let list):
                Section {
                    ForEach(list) { pixel in
                        EditorToggleRow(
                            label: pixel.name,
                            help: help(for: pixel),
                            isOn: Binding(
                                get: { attached.contains(pixel.id) },
                                set: { isOn in Task { await setAttached(pixel, isOn) } }
                            )
                        )
                        .disabled(savingID != nil)
                    }
                } footer: {
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.circle.fill")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioError)
                    }
                }
            }
        }
        .task { if pixels.value == nil { await load() } }
        .refreshable { await load() }
    }

    private func help(for pixel: BioPixel) -> String {
        let type = types[pixel.type]
        let provider = type?.name ?? pixel.type
        if type?.emitsBeacon == false {
            return String(localized: "\(provider) · can't emit on this page")
        }
        return provider
    }

    private func load() async {
        if pixels.value == nil { pixels = .loading }
        do {
            async let list = pages.client.bioPixels()
            async let kinds = pages.client.bioPixelTypes()
            let loaded = try await list
            // The provider list only adds the "can't emit" note; without it
            // the pixels are still listed and attachable.
            let providers = (try? await kinds) ?? []
            types = Dictionary(providers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            pixels = .loaded(loaded)
        } catch is CancellationError {
            if case .loading = pixels { pixels = .idle }
        } catch {
            pages.onError(error)
            if pixels.value == nil { pixels = .failed(error.asAPIError) }
        }
    }

    private func setAttached(_ pixel: BioPixel, _ isOn: Bool) async {
        var ids = attached.filter { $0 != pixel.id }
        if isOn { ids.append(pixel.id) }
        savingID = pixel.id
        defer { savingID = nil }
        do {
            try await editor.savePage(BioPageChanges(pixelIDs: ids))
            saveError = nil
        } catch {
            saveError = error.asAPIError.localizedDescription
        }
    }
}
