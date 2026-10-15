import SwiftUI
import StudioKit

/*
 EditorChrome — the toolbar every link and resource editor shares
 (DESIGN-DIRECTION "Editors"):

     Form { … }
         .navigationTitle(Text(verbatim: "/spring-menu"))
         .editorSubtitle("card.site")                 // the host, under the title
         .editorMoreMenu {                            // one … menu of secondary actions
             Button { … } label: { ResourceVerb.duplicate.label }
             Divider()
             Button(role: .destructive) { … } label: { ResourceVerb.delete.label }
         }
         .unsavedChanges(…)                           // ✕ and the one prominent ✓

 - The subtitle is `navigationSubtitle`: macOS has it; iOS from 26.
 - The … menu is `ToolbarOverflowMenu` on iOS 27 (behind the Swift 6.4
   compiler guard, so Xcode 26 CI still builds), and a `Menu` in the
   primary-action slot everywhere else.
 - ✓ and ✕ are symbols on iOS 26, where the system draws them as circular
   glass buttons; words before 26 and on the Mac, where a toolbar of
   symbols without words reads as unlabeled.
 */

/// The label of an editor's confirm (✓) or close (✕) toolbar button.
/// VoiceOver always hears the word.
struct EditorBarLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Text(title)
        }
        #else
        Text(title)
        #endif
    }

    static func save() -> EditorBarLabel {
        EditorBarLabel(title: String(localized: "Save"), systemImage: "checkmark")
    }

    static func create() -> EditorBarLabel {
        EditorBarLabel(title: String(localized: "Create"), systemImage: "checkmark")
    }

    static func cancel() -> EditorBarLabel {
        EditorBarLabel(title: String(localized: "Cancel"), systemImage: "xmark")
    }
}

extension View {
    /// The short address (or host) under the navigation title: macOS 13+
    /// and iOS 26+. Earlier iOS shows the title alone; the hero header
    /// carries the full address either way.
    @ViewBuilder
    func editorSubtitle(_ subtitle: String?) -> some View {
        if let subtitle, !subtitle.isEmpty {
            #if os(macOS)
            navigationSubtitle(Text(verbatim: subtitle))
            #elseif os(iOS)
            if #available(iOS 26.0, *) {
                navigationSubtitle(Text(verbatim: subtitle))
            } else {
                self
            }
            #else
            self
            #endif
        } else {
            self
        }
    }

    /// An editor's secondary actions (Share, Duplicate, Show Card,
    /// Statistics, Create QR Code, Delete) in one … menu.
    func editorMoreMenu<Items: View>(@ViewBuilder _ items: @escaping () -> Items) -> some View {
        modifier(EditorMoreMenu(items: items))
    }
}

private struct EditorMoreMenu<Items: View>: ViewModifier {
    let items: () -> Items

    func body(content: Content) -> some View {
        #if compiler(>=6.4) && os(iOS)
        if #available(iOS 27.0, *) {
            // The sanctioned overflow (HIG: "Don't add an overflow menu
            // manually"): the system places it and keeps it last.
            content.toolbar {
                ToolbarOverflowMenu {
                    items()
                }
            }
        } else {
            menu(content)
        }
        #else
        menu(content)
        #endif
    }

    private func menu(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    items()
                } label: {
                    Label(String(localized: "More"), systemImage: Self.symbol)
                }
                .accessibilityIdentifier("editor.more")
            }
        }
    }

    /// iOS 26 draws the bare ellipsis inside a glass circle; earlier
    /// systems use the circled glyph.
    private static var symbol: String {
        if #available(iOS 26.0, macOS 26.0, *) {
            return "ellipsis"
        }
        return "ellipsis.circle"
    }
}
