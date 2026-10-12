import Foundation
import Observation
import CardsiteKit

/// Page-wide settings while the Page Settings sheet is open.
///
/// Edits land in a local copy of `settings` and are saved shortly after the
/// last change (switches and pickers at once), always as the whole object,
/// because the server replaces `settings` on every PUT. Saves run one at a
/// time, so an older copy can never overwrite a newer one.
@MainActor
@Observable
final class PageSettingsModel {
    let editor: PageEditorModel
    private(set) var draft: [String: JSONValue]
    private(set) var isSaving = false
    private(set) var saveError: String?

    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherSave = false

    init(editor: PageEditorModel) {
        self.editor = editor
        self.draft = editor.page?.settings ?? [:]
    }

    var hasUnsavedChanges: Bool {
        guard let page = editor.page else { return false }
        return draft != page.settings
    }

    // MARK: Reading

    func value(_ key: String) -> JSONValue? { draft[key] }

    func string(_ key: String) -> String { draft[key]?.displayString ?? "" }

    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        draft[key]?.boolValue ?? fallback
    }

    func int(_ key: String) -> Int? {
        if let number = draft[key]?.intValue { return number }
        if let number = draft[key]?.doubleValue { return Int(number.rounded()) }
        return draft[key]?.stringValue.flatMap { Int($0) }
    }

    // MARK: Writing

    /// Sets one key (nil removes it). Text waits for a pause in typing;
    /// pass `immediately` for switches, pickers and picked assets.
    func set(_ key: String, _ value: JSONValue?, immediately: Bool = false) {
        guard draft[key] != value else { return }
        draft[key] = value
        if immediately {
            pendingSave?.cancel()
            pendingSave = nil
            Task { await flush() }
        } else {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.pendingSave = nil
            await self.flush()
        }
    }

    /// Saves now if anything is unsaved. Safe to call repeatedly.
    func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isSaving else {
            needsAnotherSave = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        repeat {
            needsAnotherSave = false
            guard hasUnsavedChanges else { break }
            let snapshot = draft
            do {
                try await editor.savePage(BioPageChanges(settings: snapshot))
                saveError = nil
            } catch {
                saveError = error.asAPIError.localizedDescription
                break
            }
        } while needsAnotherSave
    }

    /// Changes the address. Returns a message when it was refused.
    func changeSlug(to slug: String) async -> String? {
        if let problem = Slug.problem(with: slug) {
            return Slug.message(for: problem)
        }
        do {
            try await editor.savePage(BioPageChanges(slug: slug))
            return nil
        } catch {
            return error.asAPIError.localizedDescription
        }
    }

    /// The directory listing is a column, not a settings key.
    func setListedInDirectory(_ isListed: Bool) async {
        do {
            try await editor.savePage(BioPageChanges(directoryIsEnabled: isListed))
            saveError = nil
        } catch {
            saveError = error.asAPIError.localizedDescription
        }
    }
}
