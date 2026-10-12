import SwiftUI
import Observation

/*
 UnsavedChangesModifier — Save in the toolbar, and no edit lost by accident.

     Form { … }
         .unsavedChanges(isDirty: model.isDirty, isSaving: model.isSaving,
                         save: { await model.save() },
                         discard: { model.discard() })

 What it does:
 - A Save button (⌘S) in the confirmation slot, enabled only with changes,
   and a spinner while saving.
 - With changes, the back button is replaced by Cancel, which asks: Save,
   Discard, or Keep Editing. In a sheet it also blocks swipe-to-dismiss.
   On iPad and Mac, where the editor is the root of the detail column,
   Discard reverts the form in place.
 - It reports `isDirty` to an `UnsavedChangesTracker` in the environment,
   if there is one. A split view that owns the tracker can ask before the
   sidebar selection replaces an editor with changes:

       @State private var unsaved = UnsavedChangesTracker()
       NavigationSplitView { List(selection: unsaved.guarding($selection)) … }
           .environment(unsaved)
           .unsavedSelectionAlert(unsaved)

 `save` returns whether it succeeded, so "Save" from the prompt only leaves
 the editor once the server has the changes.
 */
struct UnsavedChangesModifier: ViewModifier {
    let isDirty: Bool
    let isSaving: Bool
    let save: @MainActor () async -> Bool
    let discard: @MainActor () -> Void
    /// The Save button's accessibility identifier, for UI tests.
    var saveIdentifier = "editor.save"

    @Environment(\.dismiss) private var dismiss
    @Environment(UnsavedChangesTracker.self) private var tracker: UnsavedChangesTracker?
    @State private var isConfirming = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(isDirty)
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                if isDirty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isConfirming = true }
                            .disabled(isSaving)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Saving"))
                    } else {
                        Button("Save") { Task { _ = await save() } }
                            .accessibilityIdentifier(saveIdentifier)
                            .disabled(!isDirty)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            .confirmationDialog("You have unsaved changes.", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Save Changes") {
                    Task {
                        if await save() { dismiss() }
                    }
                }
                Button("Discard Changes", role: .destructive) {
                    discard()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            }
            .onChange(of: isDirty, initial: true) { _, dirty in
                tracker?.isDirty = dirty
            }
            .onDisappear {
                tracker?.isDirty = false
            }
    }
}

extension View {
    func unsavedChanges(isDirty: Bool, isSaving: Bool,
                        save: @escaping @MainActor () async -> Bool,
                        discard: @escaping @MainActor () -> Void,
                        saveIdentifier: String = "editor.save") -> some View {
        modifier(UnsavedChangesModifier(isDirty: isDirty, isSaving: isSaving, save: save, discard: discard,
                                        saveIdentifier: saveIdentifier))
    }

    /// Asks before a guarded selection change throws away an editor's changes.
    func unsavedSelectionAlert(_ tracker: UnsavedChangesTracker) -> some View {
        modifier(UnsavedSelectionAlert(tracker: tracker))
    }
}

/// Whether the editor on screen has unsaved changes, for containers that
/// can replace it (a split view's sidebar selection).
@MainActor
@Observable
final class UnsavedChangesTracker {
    var isDirty = false
    /// A selection change waiting for "Discard".
    fileprivate var pendingChange: (() -> Void)?

    var isAsking: Bool { pendingChange != nil }

    /// A binding that holds a change back while the editor is dirty, and
    /// applies it only after the user chooses to discard.
    func guarding<Value: Equatable>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { [weak self] newValue in
                guard let self, newValue != binding.wrappedValue else { return }
                if self.isDirty {
                    self.pendingChange = { binding.wrappedValue = newValue }
                } else {
                    binding.wrappedValue = newValue
                }
            }
        )
    }

    fileprivate func confirm() {
        let change = pendingChange
        pendingChange = nil
        isDirty = false
        change?()
    }

    fileprivate func cancel() {
        pendingChange = nil
    }
}

private struct UnsavedSelectionAlert: ViewModifier {
    let tracker: UnsavedChangesTracker

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: Binding(get: { tracker.isAsking }, set: { if !$0 { tracker.cancel() } }),
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { tracker.confirm() }
                Button("Keep Editing", role: .cancel) { tracker.cancel() }
            } message: {
                Text("The changes you made to this item haven’t been saved.")
            }
    }
}
