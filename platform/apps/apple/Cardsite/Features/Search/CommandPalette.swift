import SwiftUI
import StudioKit
import CardsiteKit

/// The ⌘K palette on iPad and Mac: every destination, every create action
/// and the workspace's links, filtered as you type.
///
/// Chrome floating over content, so it takes the Studio glass (regular
/// variant, which keeps text legible). Fully keyboard-driven: type to
/// filter, ↑/↓ to move, Return to open, Esc to close. Pointer hover moves
/// the highlight too, and VoiceOver reads it as a modal list of buttons.
struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellRouter.self) private var router
    @Environment(QuickSearchModel.self) private var search

    @FocusState private var isFieldFocused: Bool
    @State private var highlighted = 0

    /// One row of the palette.
    enum Entry: Identifiable, Hashable {
        case destination(AppDestination)
        case create(CreateAction)
        case link(Resource)

        var id: String {
            switch self {
            case .destination(let destination): return "go-\(destination.rawValue)"
            case .create(let action): return "new-\(action.rawValue)"
            case .link(let link): return "link-\(link.id)"
            }
        }
    }

    private struct PaletteSection: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    private var sections: [PaletteSection] {
        var sections: [PaletteSection] = []
        let destinations = search.destinations.map(Entry.destination)
        if !destinations.isEmpty {
            sections.append(PaletteSection(title: String(localized: "Navigation"), entries: destinations))
        }
        let actions = search.actions.map(Entry.create)
        if !actions.isEmpty {
            sections.append(PaletteSection(title: String(localized: "Create"), entries: actions))
        }
        let links = search.linkResults.map(Entry.link)
        if search.searchesLinks, !links.isEmpty {
            sections.append(PaletteSection(title: String(localized: "Links"), entries: links))
        }
        return sections
    }

    private var entries: [Entry] { sections.flatMap(\.entries) }

    var body: some View {
        @Bindable var bindableSearch = search
        let allEntries = entries

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.studioScrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityLabel("Close search")
                    .accessibilityAddTraits(.isButton)

                VStack(spacing: 0) {
                    field(text: $bindableSearch.query, entries: allEntries)
                    Divider().overlay(Color.studioBorder)
                    results(entries: allEntries)
                        .frame(maxHeight: proxy.size.height * 0.5)
                    Divider().overlay(Color.studioBorder)
                    footer(count: allEntries.count)
                }
                .frame(maxWidth: ShellMetrics.paletteWidth)
                .studioGlass(cornerRadius: StudioRadius.xl)
                .padding(.horizontal, StudioSpace.s4)
                .padding(.top, proxy.size.height * 0.12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Command palette")
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, close)
            }
        }
        .defaultFocus($isFieldFocused, true)
        .onAppear {
            highlighted = 0
            isFieldFocused = true
        }
        .onDisappear { search.reset() }
        .onChange(of: search.query) { highlighted = 0 }
        .onChange(of: allEntries.count) { _, count in
            highlighted = min(highlighted, max(0, count - 1))
        }
        .task(id: search.query) { [search] in await search.searchLinks() }
        #if os(macOS)
        .onExitCommand(perform: close)
        #endif
    }

    // MARK: Parts

    private func field(text: Binding<String>, entries: [Entry]) -> some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: "magnifyingglass")
                .imageScale(.large)
                .foregroundStyle(Color.studioText3)
                .accessibilityHidden(true)
            TextField(text: text, prompt: Text("Search pages, actions…")) {
                Text("Search")
            }
            .textFieldStyle(.plain)
            .studioText(.lead)
            .foregroundStyle(Color.studioText)
            .focused($isFieldFocused)
            .plainEntry()
            .submitLabel(.go)
            .onSubmit { activate(at: highlighted, in: entries) }
            .onKeyPress(.downArrow) {
                guard !entries.isEmpty else { return .ignored }
                highlighted = min(highlighted + 1, entries.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !entries.isEmpty else { return .ignored }
                highlighted = max(highlighted - 1, 0)
                return .handled
            }
            .onKeyPress(.escape) {
                close()
                return .handled
            }

            if search.isSearchingLinks {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching links")
            }
            StudioKbd("esc")
                .accessibilityHidden(true)
        }
        .padding(.horizontal, StudioSpace.s5)
        .padding(.vertical, StudioSpace.s4)
    }

    /// The rows at their natural height, scrolling only once they outgrow
    /// the space the palette allows.
    private func results(entries: [Entry]) -> some View {
        ScrollViewReader { scroller in
            ViewThatFits(in: .vertical) {
                resultList(entries: entries)
                ScrollView {
                    resultList(entries: entries)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .onChange(of: highlighted) { _, index in
                guard entries.indices.contains(index) else { return }
                scroller.scrollTo(entries[index].id)
            }
        }
    }

    private func resultList(entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            if entries.isEmpty {
                emptyResults
            }
            ForEach(sections) { section in
                Text(section.title)
                    .studioText(.label)
                    .foregroundStyle(Color.studioText3)
                    .padding(.horizontal, StudioSpace.s3)
                    .padding(.top, StudioSpace.s3)
                    .padding(.bottom, StudioSpace.s1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(section.entries) { entry in
                    let index = entries.firstIndex(of: entry) ?? 0
                    row(entry, isHighlighted: index == highlighted)
                        .id(entry.id)
                        .onHover { inside in
                            if inside { highlighted = index }
                        }
                }
            }
        }
        .padding(StudioSpace.s2)
    }

    private var emptyResults: some View {
        VStack(spacing: StudioSpace.s2) {
            Image(systemName: "magnifyingglass")
                .imageScale(.large)
                .foregroundStyle(Color.studioText4)
            Text(search.isSearchingLinks ? String(localized: "Searching…") : String(localized: "No results found"))
                .studioText(.ui)
                .foregroundStyle(Color.studioText2)
            if let error = search.links.error {
                Text(error.localizedDescription)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, StudioSpace.s8)
        .accessibilityElement(children: .combine)
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        Button {
            activate(entry)
        } label: {
            HStack(spacing: StudioSpace.s3) {
                Image(systemName: symbol(for: entry))
                    .foregroundStyle(isHighlighted ? Color.studioText : Color.studioText2)
                    .frame(minWidth: StudioSpace.s6)
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(verbatim: title(for: entry))
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail = detail(for: entry) {
                        Text(verbatim: detail)
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: StudioSpace.s3)
                if let shortcut = shortcut(for: entry) {
                    StudioKbd(shortcut)
                        .accessibilityLabel(Text("Shortcut \(shortcut)"))
                }
            }
            .padding(.horizontal, StudioSpace.s3)
            .padding(.vertical, StudioSpace.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .fill(isHighlighted ? Color.studioAccentSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: StudioSpace.s4) {
            HStack(spacing: StudioSpace.s1) {
                StudioKbd("↑")
                StudioKbd("↓")
                Text("Navigate")
            }
            HStack(spacing: StudioSpace.s1) {
                StudioKbd("↩")
                Text("Open")
            }
            Spacer(minLength: StudioSpace.s2)
            Text(count == 1 ? String(localized: "1 result") : String(localized: "\(count) results"))
                .monospacedDigit()
        }
        .studioText(.uiSm)
        .foregroundStyle(Color.studioText3)
        .padding(.horizontal, StudioSpace.s5)
        .padding(.vertical, StudioSpace.s3)
        .accessibilityHidden(true)
    }

    // MARK: Entry presentation

    private func title(for entry: Entry) -> String {
        switch entry {
        case .destination(let destination): return destination.title
        case .create(let action): return action.title
        case .link(let link): return app.addresses.display(for: link.slug)
        }
    }

    private func detail(for entry: Entry) -> String? {
        switch entry {
        case .destination(let destination): return destination.group.title
        case .create(let action): return action.blurb
        case .link(let link): return link.destination
        }
    }

    private func symbol(for entry: Entry) -> String {
        switch entry {
        case .destination(let destination): return destination.systemImage
        case .create(let action): return action.systemImage
        case .link: return "link"
        }
    }

    private func shortcut(for entry: Entry) -> String? {
        switch entry {
        case .destination(let destination): return destination.shortcut.map { "⌘\($0.character)" }
        case .create(let action): return action.shortcutLabel
        case .link: return nil
        }
    }

    // MARK: Actions

    private func activate(at index: Int, in entries: [Entry]) {
        guard entries.indices.contains(index) else { return }
        activate(entries[index])
    }

    private func activate(_ entry: Entry) {
        close()
        switch entry {
        case .destination(let destination):
            router.open(destination)
        case .create(let action):
            app.composer = action.composer
        case .link(let link):
            router.presentedLink = link
        }
    }

    private func close() {
        router.isPalettePresented = false
        search.reset()
    }
}

enum ShellMetrics {
    /// The palette's width on wide windows; it narrows with the window.
    static let paletteWidth: CGFloat = 600
}

#if DEBUG
#Preview("Command palette") {
    let app = AppModel.preview()
    let router = ShellRouter()
    router.isPalettePresented = true
    return Color.studioBg
        .overlay { CommandPalette() }
        .environment(app)
        .environment(router)
        .environment(QuickSearchModel(client: app.client))
}
#endif
