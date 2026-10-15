import SwiftUI
import StudioKit

/// The head of a section within an editorial page (Home, Library): Studio
/// 1.10's quiet `StudioSectionHeader` — a `.label` title and a sentence-case
/// note — announced as a heading so VoiceOver's rotor can jump between
/// sections.
///
/// It used to be a kicker over a two-tone `.title`, which gave every
/// section the weight of a page head. The page head is a page's one focal
/// element (DESIGN.md §Composition); sections sit under it, quietly.
///
/// The title is an uppercase style: a word or two, never a sentence. Put
/// the sentence in `note`.
///
///     PageSectionHead(String(localized: "Create"),
///                     note: String(localized: "Shorten a link, or start any type."))
struct PageSectionHead: View {
    let title: String
    var note: String? = nil

    init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    var body: some View {
        StudioSectionHeader(title, note: note)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Section heads") {
    VStack(alignment: .leading, spacing: StudioSpace.s8) {
        PageSectionHead("Create", note: "Shorten a link in one move, or start any type.")
        PageSectionHead("At a glance")
    }
    .padding(StudioSpace.s6)
    .background(Color.studioBg)
}
#endif
