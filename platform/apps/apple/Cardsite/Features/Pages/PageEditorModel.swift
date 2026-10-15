import Foundation
import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Unsaved edits to one block: its whole `settings` object and its
/// `location_url` column, because a PUT replaces `settings` whole.
struct BlockDraft: Equatable, Sendable {
    var settings: [String: JSONValue]
    var locationURL: String

    init(block: BioBlock) {
        settings = block.settings
        locationURL = block.locationURL ?? ""
    }

    func differs(from block: BioBlock) -> Bool {
        settings != block.settings || locationURL != (block.locationURL ?? "")
    }
}

/// One bio page open for editing: its blocks, the selection, unsaved block
/// drafts, and every write the editor makes.
@MainActor
@Observable
final class PageEditorModel {
    struct Conflict: Identifiable, Equatable {
        let blockID: Int
        let editorName: String?
        var id: Int { blockID }
    }

    let pageID: Int
    let pages: PagesModel

    private(set) var state: Loadable<BioPageDocument> = .idle
    private(set) var refreshError: APIError?
    /// The block open in the inspector.
    var selection: BioBlock.ID?
    private(set) var drafts: [Int: BlockDraft] = [:]
    private(set) var savingBlockIDs: Set<Int> = []
    private(set) var busyBlockIDs: Set<Int> = []
    /// The block whose save just finished, for a moment, so the inspector
    /// can say "Saved".
    private(set) var savedBlockID: Int?
    var conflict: Conflict?
    /// Bumped after every write that changes the public page, so the
    /// preview reloads.
    private(set) var previewRevision = 0

    @ObservationIgnored private var savedReset: Task<Void, Never>?
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }
    /// Short confirmations and failures, shown as Studio toasts.
    @ObservationIgnored var announce: @MainActor (String, StudioToast.Variant) -> Void = { _, _ in }

    private var client: APIClient { pages.client }

    init(pageID: Int, pages: PagesModel, document: BioPageDocument? = nil) {
        self.pageID = pageID
        self.pages = pages
        if let document { state = .loaded(document) }
    }

    var page: BioPage? { state.value?.page }
    var blocks: [BioBlock] { state.value?.blocks ?? [] }

    func block(_ id: BioBlock.ID?) -> BioBlock? {
        guard let id else { return nil }
        return blocks.first { $0.id == id }
    }

    var selectedBlock: BioBlock? { block(selection) }

    /// Loaded, with no blocks yet.
    var isEmpty: Bool { state.value.map { $0.blocks.isEmpty } ?? false }

    func blockType(for block: BioBlock) -> BlockType? {
        pages.blockType(block.type)
    }

    /// A duplicate is a create, so a premium type the plan lacks can't be copied.
    func isDuplicateLocked(_ block: BioBlock) -> Bool {
        guard let type = blockType(for: block), type.isPremium else { return false }
        return !pages.allows(PagesModel.Capability.premiumBlocks)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        if case .idle = state { await load() }
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            let document = try await client.bioPage(id: pageID)
            state = .loaded(document)
            refreshError = nil
            pages.pageDidChange(document.page)
            if let selection, !document.blocks.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
            // Drafts for blocks that are gone, or that now match what is
            // stored, are dropped.
            drafts = drafts.filter { id, draft in
                guard let block = document.blocks.first(where: { $0.id == id }) else { return false }
                return draft.differs(from: block)
            }
        } catch is CancellationError {
            if case .loading = state { state = .idle }
        } catch {
            let apiError = error.asAPIError
            onError(apiError)
            if state.value == nil {
                state = .failed(apiError)
            } else {
                refreshError = apiError
            }
        }
    }

    func dismissRefreshError() { refreshError = nil }

    private func mutate(_ change: (inout BioPageDocument) -> Void) {
        guard var document = state.value else { return }
        change(&document)
        state = .loaded(document)
    }

    private func replace(_ block: BioBlock) {
        mutate { document in
            if let index = document.blocks.firstIndex(where: { $0.id == block.id }) {
                document.blocks[index] = block
            }
        }
    }

    private func pageWasWritten() {
        previewRevision += 1
    }

    /// Loads the preview again without a write (Reload, Try Again).
    func reloadPreview() {
        previewRevision += 1
    }

    private func markSaved(_ id: Int) {
        savedBlockID = id
        savedReset?.cancel()
        savedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.savedBlockID = nil
        }
    }

    // MARK: Drafts

    func draft(for block: BioBlock) -> BlockDraft {
        drafts[block.id] ?? BlockDraft(block: block)
    }

    func hasUnsavedChanges(_ block: BioBlock) -> Bool {
        drafts[block.id].map { $0.differs(from: block) } ?? false
    }

    var hasAnyUnsavedChanges: Bool {
        blocks.contains { hasUnsavedChanges($0) }
    }

    /// The value a field shows: the draft's, else the stored one.
    func value(_ field: String, in block: BioBlock) -> JSONValue? {
        let draft = draft(for: block)
        if field == "location_url" {
            return draft.locationURL.isEmpty ? nil : .string(draft.locationURL)
        }
        return draft.settings[field]
    }

    /// Sets one field of a block's draft. Nil removes the key.
    func setValue(_ value: JSONValue?, for field: String, in block: BioBlock) {
        var draft = draft(for: block)
        if field == "location_url" {
            draft.locationURL = value?.displayString ?? ""
        } else {
            draft.settings[field] = value
        }
        drafts[block.id] = draft
        if savedBlockID == block.id { savedBlockID = nil }
    }

    func revert(_ block: BioBlock) {
        drafts[block.id] = nil
    }

    // MARK: Block writes

    /// Saves a block's draft: the whole `settings` object, the
    /// `location_url` when the type has one, and the version it was loaded at.
    @discardableResult
    func save(_ block: BioBlock) async -> Bool {
        guard let draft = drafts[block.id], draft.differs(from: block), !savingBlockIDs.contains(block.id) else {
            return true
        }
        savingBlockIDs.insert(block.id)
        defer { savingBlockIDs.remove(block.id) }
        let hasLocation = blockType(for: block)?.fields.contains { $0.name == "location_url" }
            ?? (block.locationURL != nil)
        do {
            let saved = try await client.updateBlock(
                id: block.id,
                version: block.version,
                settings: draft.settings,
                locationURL: hasLocation ? draft.locationURL.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            )
            replace(saved)
            // Keep any typing that happened while the request was out.
            if drafts[block.id] == draft { drafts[block.id] = nil }
            pageWasWritten()
            markSaved(block.id)
            return true
        } catch let conflict as BlockConflictError {
            self.conflict = Conflict(blockID: block.id, editorName: conflict.lastEditorName)
            return false
        } catch {
            onError(error)
            announce(error.asAPIError.localizedDescription, .error)
            return false
        }
    }

    /// Saves every block with unsaved edits, for when the editor closes.
    func saveAllDrafts() async {
        for block in blocks where hasUnsavedChanges(block) {
            await save(block)
        }
    }

    /// After a 409: drop this block's draft and load what is stored now.
    /// Pass the conflict the alert showed: dismissing the alert clears
    /// `conflict` before this runs.
    func reloadAfterConflict(_ resolved: Conflict? = nil) async {
        if let blockID = (resolved ?? conflict)?.blockID { drafts[blockID] = nil }
        conflict = nil
        await load()
    }

    func setEnabled(_ block: BioBlock, _ isEnabled: Bool) async {
        guard !busyBlockIDs.contains(block.id) else { return }
        busyBlockIDs.insert(block.id)
        defer { busyBlockIDs.remove(block.id) }
        // Optimistic: the switch moves at once and moves back on failure.
        var optimistic = block
        optimistic.isEnabled = isEnabled
        replace(optimistic)
        do {
            let saved = try await client.updateBlock(id: block.id, version: block.version, isEnabled: isEnabled)
            replace(saved)
            pageWasWritten()
        } catch let conflict as BlockConflictError {
            replace(block)
            self.conflict = Conflict(blockID: block.id, editorName: conflict.lastEditorName)
        } catch {
            replace(block)
            onError(error)
            announce(String(localized: "Couldn’t update this block. \(error.asAPIError.localizedDescription)"), .error)
        }
    }

    /// Adds a block of `type` at the end, with the web's starter content,
    /// and selects it.
    @discardableResult
    func add(_ type: BlockType) async -> Bool {
        do {
            let block = try await client.createBlock(
                pageID: pageID,
                type: type.type,
                settings: BlockDefaults.settings(for: type.type),
                order: blocks.count
            )
            mutate { $0.blocks.append(block) }
            selection = block.id
            pageWasWritten()
            await persistOrder(restoringOnFailure: nil)
            return true
        } catch {
            onError(error)
            announce(error.asAPIError.localizedDescription, .error)
            return false
        }
    }

    /// Copies a block (its saved settings) to just below it.
    func duplicate(_ block: BioBlock) async {
        guard !busyBlockIDs.contains(block.id) else { return }
        busyBlockIDs.insert(block.id)
        defer { busyBlockIDs.remove(block.id) }
        do {
            let copy = try await client.createBlock(
                pageID: pageID,
                type: block.type,
                settings: block.settings,
                locationURL: block.locationURL,
                order: blocks.count
            )
            mutate { document in
                let index = document.blocks.firstIndex { $0.id == block.id } ?? (document.blocks.count - 1)
                document.blocks.insert(copy, at: min(index + 1, document.blocks.count))
            }
            selection = copy.id
            pageWasWritten()
            await persistOrder(restoringOnFailure: nil)
        } catch {
            onError(error)
            announce(error.asAPIError.localizedDescription, .error)
        }
    }

    func delete(_ block: BioBlock) async {
        guard !busyBlockIDs.contains(block.id) else { return }
        busyBlockIDs.insert(block.id)
        defer { busyBlockIDs.remove(block.id) }
        do {
            try await client.deleteBlock(id: block.id)
            mutate { $0.blocks.removeAll { $0.id == block.id } }
            drafts[block.id] = nil
            if selection == block.id { selection = nil }
            pageWasWritten()
        } catch {
            onError(error)
            announce(String(localized: "Couldn’t delete this block. \(error.asAPIError.localizedDescription)"), .error)
        }
    }

    // MARK: Order

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let previous = blocks
        mutate { $0.blocks.move(fromOffsets: source, toOffset: destination) }
        guard blocks.map(\.id) != previous.map(\.id) else { return }
        Task { await persistOrder(restoringOnFailure: previous) }
    }

    func canMove(_ block: BioBlock, by offset: Int) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return false }
        return blocks.indices.contains(index + offset)
    }

    func move(_ block: BioBlock, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }), canMove(block, by: offset) else { return }
        // `move(fromOffsets:toOffset:)` counts the destination before removal.
        move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? index + offset + 1 : index + offset)
    }

    /// Sends the current order. On failure, puts `previous` back.
    private func persistOrder(restoringOnFailure previous: [BioBlock]?) async {
        let ids = blocks.map(\.id)
        guard ids.count > 1 else { return }
        do {
            try await client.reorderBlocks(ids)
            mutate { document in
                for index in document.blocks.indices { document.blocks[index].order = index }
            }
            pageWasWritten()
        } catch {
            onError(error)
            if let previous { mutate { $0.blocks = previous } }
            announce(String(localized: "Couldn’t reorder the blocks. The previous order is back."), .error)
        }
    }

    // MARK: Page writes

    /// Writes page-level fields and keeps the list row in step.
    func savePage(_ changes: BioPageChanges) async throws {
        do {
            let updated = try await client.updateBioPage(id: pageID, changes)
            mutate { $0.page = updated }
            pages.pageDidChange(updated)
            pageWasWritten()
        } catch {
            onError(error)
            throw error
        }
    }
}

// MARK: - Starter content

/// What a new block starts with, from apps/web/src/lib/blockDefaults.ts:
/// plausible text the author edits, never a real-looking address.
enum BlockDefaults {
    static func settings(for type: String) -> [String: JSONValue] {
        switch type {
        case "link": return ["name": .string(String(localized: "Untitled link"))]
        case "heading": return ["heading": .string(String(localized: "Your heading"))]
        case "paragraph": return ["paragraph": .string(String(localized: "Write something about yourself here."))]
        case "header": return ["title": .string(String(localized: "Section title"))]
        case "socials": return ["socials": .array([])]
        case "big_link", "featured_link": return ["name": .string(String(localized: "Featured link"))]
        case "cta": return ["name": .string(String(localized: "Get in touch"))]
        case "alert":
            return ["alert_type": "info", "alert_text": .string(String(localized: "Something worth knowing."))]
        case "list": return ["items": .array([])]
        case "markdown": return ["markdown": .string(String(localized: "### Heading\n\nSome text."))]
        case "custom_html": return ["custom_html": .string(String(localized: "<p>Your HTML here.</p>"))]
        case "code": return ["code": "", "language": "javascript"]
        case "email_collector":
            return ["name": .string(String(localized: "Subscribe")), "button_text": .string(String(localized: "Subscribe"))]
        case "phone_collector":
            return ["name": .string(String(localized: "Get updates")), "button_text": .string(String(localized: "Send"))]
        case "contact_collector":
            return ["name": .string(String(localized: "Contact me")), "button_text": .string(String(localized: "Send"))]
        case "faq":
            return ["items": [["title": .string(String(localized: "A question")), "content": .string(String(localized: "The answer."))]]]
        case "timeline":
            return ["items": [["title": .string(String(localized: "A milestone")), "content": .string(String(localized: "What happened."))]]]
        case "business_hours": return ["hours": .array([])]
        case "countdown": return ["name": .string(String(localized: "Counting down"))]
        case "share": return ["name": .string(String(localized: "Share this page"))]
        case "coupon": return ["name": .string(String(localized: "Your discount")), "code": "SAVE10"]
        case "review": return ["name": .string(String(localized: "What people say")), "rating": 5]
        case "counter": return ["name": .string(String(localized: "Counter")), "value": 0]
        case "progress_bar": return ["title": .string(String(localized: "Progress")), "current": 0, "goal": 100]
        case "social_proof": return ["title": .string(String(localized: "people")), "count": 0]
        case "modal_text":
            return [
                "name": .string(String(localized: "Read more")),
                "title": .string(String(localized: "More detail")),
                "content": .string(String(localized: "The detail.")),
            ]
        case "image_grid", "image_slider": return ["images": .array([])]
        case "external_item": return ["name": .string(String(localized: "Item"))]
        case "appointment_calendar": return ["name": .string(String(localized: "Book a time"))]
        case "donation": return ["title": .string(String(localized: "Support my work")), "currency": "$"]
        case "product": return ["title": .string(String(localized: "A product")), "currency": "$"]
        case "service": return ["title": .string(String(localized: "A service")), "currency": "$"]
        case "paypal": return ["name": .string(String(localized: "Pay with PayPal"))]
        case "cashapp": return ["name": .string(String(localized: "Pay on Cash App"))]
        case "venmo": return ["name": .string(String(localized: "Pay on Venmo"))]
        case "vcard": return ["button_text": .string(String(localized: "Save contact"))]
        case "linkedin_profile": return ["name": "LinkedIn"]
        case "instagram_feed": return ["name": .string(String(localized: "View on Instagram"))]
        default: return [:]
        }
    }
}
