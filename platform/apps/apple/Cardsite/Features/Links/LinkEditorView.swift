import SwiftUI
import StudioKit
import CardsiteKit

/// Creates a short link: a destination and an address on card.site.
///
/// A calm grouped form in a sheet (medium and large detents on iPhone):
/// the destination first, with Paste, then the address with Shuffle, and
/// a live preview of the address it makes. ✕ closes (Esc); ✓ creates
/// (⌘S, Return in the address field).
///
/// The address starts as a random 7-character slug the user can keep or
/// replace. The server never generates one, and it checks availability only
/// on create, so "taken" is reported against the address field.
///
/// `prefill` starts the destination field with a URL (Home's paste-a-URL,
/// the share extension); focus then goes to the address. Scheduling,
/// gating, cloaking, UTM and the rest are set on the link's page afterwards,
/// as on the web.
struct LinkEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(LinksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onCreated: (Resource) -> Void = { _ in }

    @State private var destination: String
    @State private var slug = Slug.random()
    @State private var destinationError: String? = nil
    @State private var slugError: String? = nil
    @State private var formError: String? = nil
    @State private var isSaving = false
    @FocusState private var focus: Field?

    enum Field { case destination, slug }

    private let prefill: URL?

    init(prefill: URL? = nil, onCreated: @escaping (Resource) -> Void = { _ in }) {
        self.prefill = prefill
        self.onCreated = onCreated
        _destination = State(initialValue: prefill?.absoluteString ?? "")
    }

    private var canCreate: Bool {
        !destination.trimmingCharacters(in: .whitespaces).isEmpty && !slug.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                addressSection
                if let formError {
                    Section {
                        FormErrorText(message: formError)
                    }
                    .studioRowBackground()
                }
            }
            .studioForm(measure: .sheet)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("link.editor")
            .navigationTitle("New Short Link")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { EditorBarLabel.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Creating"))
                    } else {
                        Button { Task { await save() } } label: { EditorBarLabel.create() }
                            .accessibilityIdentifier("link.editor.save")
                            .keyboardShortcut("s", modifiers: .command)
                            .tint(Color.studioAccentLine)
                            .disabled(!canCreate)
                    }
                }
            }
            .onChange(of: destination) { destinationError = nil; formError = nil }
            .onChange(of: slug) { slugError = nil; formError = nil }
            .defaultFocus($focus, prefill == nil ? .destination : .slug)
            .interactiveDismissDisabled(isSaving)
            .animation(reduceMotion ? nil : StudioAnimation.base, value: formError)
        }
        .cardsiteSheet(.form)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: Sections

    private var destinationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text("Destination")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .accessibilityHidden(true)
                HStack(spacing: StudioSpace.s2) {
                    TextField(String(localized: "Destination"), text: $destination,
                              prompt: Text(verbatim: "example.com/menu"))
                        .labelsHidden()
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .accessibilityIdentifier("link.editor.destination")
                        .focused($focus, equals: .destination)
                        .plainEntry()
                        #if os(iOS) || os(visionOS)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        #endif
                        .submitLabel(.next)
                        .onSubmit { focus = .slug }
                    if destination.isEmpty {
                        // The system Paste control: no permission prompt,
                        // and it only appears to act when there is text.
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !text.isEmpty else { return }
                            // Back on the main actor whatever queue the
                            // system calls this on.
                            Task { @MainActor in
                                destination = text
                                focus = .slug
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
                EditorFieldFootnote(help: String(localized: "Where the short address sends people."),
                                    error: destinationError)
            }
            .padding(.vertical, StudioSpace.s1)
        } header: {
            EditorSectionHeader(String(localized: "Destination"))
        } footer: {
            Text("You can change it later: the address and any QR codes follow.")
        }
        .studioRowBackground()
    }

    private var addressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text("Address")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .accessibilityHidden(true)
                HStack(spacing: StudioSpace.s2) {
                    TextField(String(localized: "Address"), text: $slug, prompt: Text(verbatim: "Spring-Menu"))
                        .labelsHidden()
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .accessibilityIdentifier("link.editor.slug")
                        .focused($focus, equals: .slug)
                        .plainEntry()
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                    Button {
                        slug = Slug.random()
                        slugError = nil
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text("Generates a new random address"))
                }
                EditorFieldFootnote(help: String(localized: "Letters, numbers, hyphens and underscores."),
                                    error: slugError)
            }
            .padding(.vertical, StudioSpace.s1)

            LabeledContent {
                Text(verbatim: app.addresses.display(for: slug.isEmpty ? "…" : slug))
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.opacity)
            } label: {
                Text("Your link")
                    .foregroundStyle(Color.studioText2)
            }
            .accessibilityElement(children: .combine)
        } header: {
            EditorSectionHeader(String(localized: "Address"))
        } footer: {
            Text("Scheduling, targeting and passwords are on the link’s page once it exists.")
        }
        .studioRowBackground()
    }

    // MARK: Create

    private func save() async {
        guard !isSaving else { return }
        var valid = true
        let url = Destination.normalized(destination)
        if url == nil {
            destinationError = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
            valid = false
        }
        if let problem = Slug.problem(with: slug) {
            slugError = Slug.message(for: problem)
            valid = false
        }
        guard valid, let url else {
            focus = destinationError != nil ? .destination : .slug
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let link = try await model.create(slug: slug, destination: url)
            Haptics.success()
            onCreated(link)
            dismiss()
        } catch let error as APIError {
            switch error {
            case .conflict:
                slugError = error.localizedDescription
                focus = .slug
            default:
                formError = error.localizedDescription
            }
        } catch {
            formError = error.localizedDescription
        }
    }
}

#Preview("New short link") {
    let app = AppModel(configuration: .preview)
    LinkEditorView(prefill: URL(string: "https://example.com/spring-menu"))
        .environment(app)
        .environment(LinksModel(client: app.client))
}

#Preview("New short link, empty") {
    let app = AppModel(configuration: .preview)
    LinkEditorView()
        .environment(app)
        .environment(LinksModel(client: app.client))
}
