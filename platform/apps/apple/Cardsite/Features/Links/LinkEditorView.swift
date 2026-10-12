import SwiftUI
import StudioKit
import CardsiteKit

/// Creates a short link: a destination and an address on card.site.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioSpace.s5) {
                    StudioTextField(
                        String(localized: "Destination"),
                        text: $destination,
                        placeholder: "example.com/menu",
                        help: String(localized: "Where the short address sends people."),
                        errorMessage: destinationError
                    )
                    .accessibilityIdentifier("link.editor.destination")
                    .focused($focus, equals: .destination)
                    .plainEntry()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    #endif
                    .submitLabel(.next)
                    .onSubmit { focus = .slug }

                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        StudioTextField(
                            String(localized: "Address"),
                            text: $slug,
                            placeholder: "Spring-Menu",
                            help: String(localized: "Letters, numbers, hyphens and underscores."),
                            errorMessage: slugError
                        )
                        .accessibilityIdentifier("link.editor.slug")
                        .focused($focus, equals: .slug)
                        .plainEntry()
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }

                        HStack(spacing: StudioSpace.s1) {
                            Text(verbatim: app.addresses.display(for: slug.isEmpty ? "…" : slug))
                                .studioText(.uiSm)
                                .foregroundStyle(Color.studioText2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                slug = Slug.random()
                                slugError = nil
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityHint("Generates a new random address")
                        }
                    }

                    FormErrorText(message: formError)
                }
                .padding(StudioSpace.s6)
                .readableWidth(560)
            }
            .background(Color.studioBg)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("link.editor")
            .navigationTitle("New Short Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await save() } }
                            .accessibilityIdentifier("link.editor.save")
                            .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty || slug.isEmpty)
                    }
                }
            }
            .onChange(of: destination) { destinationError = nil; formError = nil }
            .onChange(of: slug) { slugError = nil; formError = nil }
            .defaultFocus($focus, prefill == nil ? .destination : .slug)
            .interactiveDismissDisabled(isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }

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
