import SwiftUI
import StudioKit
import CardsiteKit

/*
 AddressField — slug, domain and the live URL, as rows of a Form section.

 Every resource with an address (short links, bio pages, vCards, events,
 files, static pages) is a row in `links`, addressed by a slug and an
 optional custom domain. This is the one control for that pair, so every
 editor shows the same three things in the same order.

     Section {
         AddressField(slug: $form.slug, domainID: $form.domainID,
                      domains: options.usableDomains(keeping: form.domainID),
                      defaultHost: app.addresses.publicHost,
                      error: errors[.slug])
     } header: { EditorSectionHeader(String(localized: "Address & destination")) }

 - `domains` should already be filtered to verified, enabled domains
   (`ResourceOptionsModel.usableDomains(keeping:)`). With none, the picker is
   left out and the address lives on `defaultHost`.
 - The live URL row previews the address as typed. Copy and Open act on it
   only when it is valid, so nobody copies an address that doesn't exist yet.
 - `AddressField.liveURL(…)` is the same rule for callers that need the URL
   (headers, share buttons).
 */
struct AddressField: View {
    @Binding var slug: String
    @Binding var domainID: Int?
    let domains: [DomainOption]
    let defaultHost: String
    var label: String = String(localized: "Short URL alias")
    var help: String = String(localized: "Letters, numbers, hyphens and underscores.")
    var prompt: String = String(localized: "my-link")
    var error: String?
    /// Whether the address as typed is the saved one (Copy and Open act on
    /// the saved address only).
    var isSaved: Bool = true

    @State private var copied = false

    var body: some View {
        EditorTextField(label, text: $slug, prompt: prompt, kind: .plain, help: help, error: error)

        if !domains.isEmpty {
            Picker(selection: $domainID) {
                Text(verbatim: defaultHost).tag(Int?.none)
                ForEach(domains) { domain in
                    Text(verbatim: domain.host).tag(Int?.some(domain.id))
                }
            } label: {
                Text("Domain")
            }
        }

        LabeledContent {
            HStack(spacing: StudioSpace.s2) {
                if isSaved, let url {
                    Button {
                        Pasteboard.copy(url.absoluteString)
                        Haptics.success()
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(copied ? Text("Copied") : Text("Copy address"))
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Open address"))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text("Live URL")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                Text(verbatim: display)
                    .studioText(.ui)
                    .foregroundStyle(url == nil ? Color.studioText3 : Color.studioText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if !isSaved {
                    Text("Save to use this address.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var url: URL? {
        Self.liveURL(slug: slug, domainID: domainID, domains: domains, defaultHost: defaultHost)
    }

    private var display: String {
        let shownSlug = slug.isEmpty ? "…" : slug
        if let domainID, let domain = domains.first(where: { $0.id == domainID }) {
            return "\(domain.host)/\(shownSlug)"
        }
        return "\(defaultHost)/\(shownSlug)"
    }

    /// The public URL for `slug` on the chosen domain, or nil while the slug
    /// is not a valid address.
    static func liveURL(slug: String, domainID: Int?, domains: [DomainOption], defaultHost: String) -> URL? {
        guard Slug.problem(with: slug) == nil else { return nil }
        if let domainID, let domain = domains.first(where: { $0.id == domainID }) {
            return domain.url(for: slug)
        }
        return URL(string: "https://\(defaultHost)/\(slug)")
    }
}

#Preview("Address field") {
    @Previewable @State var slug = "spring-menu"
    @Previewable @State var domainID: Int? = nil
    Form {
        Section {
            AddressField(slug: $slug, domainID: $domainID,
                         domains: [DomainOption(id: 3, host: "go.example.com")],
                         defaultHost: "card.site")
        }
        .editorRowBackground()
    }
    .resourceEditorForm()
}
