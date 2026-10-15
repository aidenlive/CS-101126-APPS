import SwiftUI
import StudioKit
import CardsiteKit

/// "Add block": every block type, searchable and grouped by category in the
/// web palette's order. Types the plan doesn't include are shown, locked,
/// with one calm sentence about why.
///
/// After a successful add the presenter decides what comes next (on
/// iPhone the new block's inspector replaces this sheet), so the sheet
/// doesn't dismiss itself then; Cancel does.
struct BlockLibrarySheet: View {
    @Environment(PagesModel.self) private var pages
    @Environment(\.dismiss) private var dismiss

    let onAdd: @MainActor (BlockType) async -> Bool

    @State private var query = ""
    @State private var adding: BlockType.ID? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch pages.blockTypes {
                case .idle, .loading:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading")
                case .failed(let error):
                    ErrorStateView(error: error) { [pages] in await pages.loadCatalog() }
                case .loaded(let types):
                    library(types)
                }
            }
            .background(Color.studioBg)
            .navigationTitle("Add a Block")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: Text("Search blocks"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await pages.loadCatalogIfNeeded() }
        .interactiveDismissDisabled(adding != nil)
        .cardsiteSheet(.form)
    }

    private func library(_ types: [BlockType]) -> some View {
        let groups = Self.groups(types, matching: query)
        let premiumLocked = !pages.allows(PagesModel.Capability.premiumBlocks)
        return List {
            if premiumLocked, query.isEmpty {
                Section {
                    StudioBanner(
                        lead: String(localized: "Some blocks aren’t in your plan."),
                        message: String(localized: "They’re marked with a lock. Blocks of those types already on your pages keep working, and you can still edit them."),
                        tone: .info
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.category) { group in
                Section {
                    ForEach(group.types) { type in
                        let isLocked = type.isPremium && premiumLocked
                        LibraryRow(type: type, isLocked: isLocked, isAdding: adding == type.id) {
                            Task { await add(type) }
                        }
                        .disabled(isLocked || adding != nil)
                    }
                } header: {
                    Text(BlockCategory.title(group.category))
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func add(_ type: BlockType) async {
        adding = type.id
        let added = await onAdd(type)
        adding = nil
        if added {
            Haptics.success()
        }
    }

    static func groups(_ types: [BlockType], matching query: String) -> [(category: String, types: [BlockType])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty ? types : types.filter {
            "\($0.name) \($0.type.replacingOccurrences(of: "_", with: " "))".localizedCaseInsensitiveContains(trimmed)
        }
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return grouped
            .map { (category: $0.key, types: $0.value) }
            .sorted {
                let left = BlockCategory.rank($0.category)
                let right = BlockCategory.rank($1.category)
                return left == right ? $0.category < $1.category : left < right
            }
    }
}

private struct LibraryRow: View {
    let type: BlockType
    let isLocked: Bool
    let isAdding: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s3) {
                BlockGlyphTile(type: type.type, color: type.color)
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(type.name)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                    if isLocked {
                        Text("Not included in your plan")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                Spacer(minLength: StudioSpace.s2)
                if isAdding {
                    ProgressView()
                } else {
                    Image(systemName: isLocked ? "lock" : "plus.circle")
                        .imageScale(.large)
                        .foregroundStyle(isLocked ? Color.studioText4 : Color.studioAccentLine)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? Text("\(type.name), not included in your plan") : Text("Add \(type.name)"))
    }
}
