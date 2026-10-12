import SwiftUI
import StudioKit
import CardsiteKit

// MARK: - Display rules

/// Audience targeting for the page: the shared `DisplayRulesSection` over
/// the server's own vocabulary (`GET /reference/targeting`), written to
/// `display_rules`.
///
/// Page settings save as you go, so a change is sent once the picking
/// pauses, and again on leaving if it hasn't gone yet. The web also shows
/// a scheduling toggle that writes `display_rules.scheduled_*`, which no
/// server code reads for bio pages, so it is left out here.
struct DisplayRulesForm: View {
    @Environment(PagesModel.self) private var pages
    let editor: PageEditorModel

    @State private var options: Loadable<TargetingOptions> = .idle
    /// Rules picked but not saved yet; nil once the server has them.
    @State private var draft: DisplayRules? = nil
    @State private var isSaving = false
    @State private var saveError: String? = nil

    private var saved: DisplayRules { DisplayRules(json: editor.page?.displayRules ?? [:]) }
    private var rules: DisplayRules { draft ?? saved }

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
            } footer: {
                if isSaving {
                    Text("Saving…")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .editorRowBackground()

            if case .failed = options {
                Section {
                    Button("Try Again") { Task { await load() } }
                }
                .editorRowBackground()
            }

            DisplayRulesSection(
                rules: Binding(get: { rules }, set: { draft = $0 }),
                options: options.value,
                loadFailed: options.error != nil,
                isLocked: !pages.allows(PagesModel.Capability.targeting),
                error: saveError
            )
        }
        .task { if options.value == nil { await load() } }
        .task(id: draft) { await saveDraft(after: .milliseconds(600)) }
        .onDisappear {
            Task { await saveDraft(after: .zero) }
        }
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

    /// Sends the draft once it has been still for `delay`. The whole object
    /// goes back: other keys (`cities`, conditions) ride along in
    /// `DisplayRules.other`.
    private func saveDraft(after delay: Duration) async {
        guard let pending = draft, pending != saved else { return }
        if delay > .zero {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await editor.savePage(BioPageChanges(displayRules: pending.json))
            saveError = nil
            if draft == pending { draft = nil }
        } catch is CancellationError {
            // A newer pick replaced this one; it saves instead.
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

    /// The list and the provider names, in a model so `.refreshable`'s
    /// `@Sendable` closure captures it rather than the view.
    @State private var catalog = PixelCatalog()
    @State private var savingID: BioPixel.ID? = nil
    @State private var saveError: String? = nil

    private var pixels: Loadable<[BioPixel]> { catalog.pixels }
    private var types: [String: BioPixelType] { catalog.types }
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
                    Button("Try Again") { Task { await catalog.load(from: pages) } }
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
        .task { [catalog, pages] in if catalog.pixels.value == nil { await catalog.load(from: pages) } }
        .refreshable { [catalog, pages] in await catalog.load(from: pages) }
    }

    private func help(for pixel: BioPixel) -> String {
        let type = types[pixel.type]
        let provider = type?.name ?? pixel.type
        if type?.emitsBeacon == false {
            return String(localized: "\(provider) · can't emit on this page")
        }
        return provider
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

/// The workspace's pixels and the providers' names, for `PixelsForm`.
@MainActor
@Observable
final class PixelCatalog {
    private(set) var pixels: Loadable<[BioPixel]> = .idle
    private(set) var types: [String: BioPixelType] = [:]

    func load(from pages: PagesModel) async {
        if pixels.value == nil { pixels = .loading }
        do {
            let client = pages.client
            async let list = client.bioPixels()
            async let kinds = client.bioPixelTypes()
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
}
