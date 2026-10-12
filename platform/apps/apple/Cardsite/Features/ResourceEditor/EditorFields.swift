import SwiftUI
import StudioKit

/*
 Form rows shared by every resource editor.

 Resource editors are native grouped `Form`s on Studio surfaces:

     Form {
         Section { EditorTextField(String(localized: "Destination URL"), text: $form.destination,
                                   prompt: "https://example.com", kind: .url,
                                   error: errors[.destination]) }
         ScheduleSection(…)
         GatingSection(…)
     }
     .resourceEditorForm()

 `EditorTextField` puts the label above the field (iOS grouped forms hide a
 text field's own label), keeps it for VoiceOver, and shows either the help
 line or the inline error under it. `LockedFeatureNote` says plainly that a
 plan doesn't include something, with no offer to buy and no link anywhere.
 */

struct EditorTextField: View {
    enum Kind {
        /// Free text with autocorrection.
        case text
        /// Addresses, slugs, UTM values: no autocapitalisation or autocorrection.
        case plain
        case url
        case number
    }

    let title: String
    @Binding var text: String
    var prompt: String = ""
    var kind: Kind = .text
    var help: String?
    var error: String?

    init(_ title: String, text: Binding<String>, prompt: String = "", kind: Kind = .text,
         help: String? = nil, error: String? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.kind = kind
        self.help = help
        self.error = error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            Text(title)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .accessibilityHidden(true)
            field
                .studioText(.ui)
                .foregroundStyle(Color.studioText)
            EditorFieldFootnote(help: help, error: error)
        }
        .padding(.vertical, StudioSpace.s1)
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(title, text: $text, prompt: Text(prompt))
            .labelsHidden()
        switch kind {
        case .text:
            base
        case .plain:
            base.plainEntry()
        case .url:
            base
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .keyboardType(.URL)
                .textContentType(.URL)
                #endif
        case .number:
            base
                #if os(iOS) || os(visionOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

/// A help line, or the inline error in its place.
struct EditorFieldFootnote: View {
    let help: String?
    let error: String?

    var body: some View {
        if let error {
            FormErrorText(message: error)
        } else if let help {
            Text(help)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Not included in your plan", stated, never sold.
struct LockedFeatureNote: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock")
                .foregroundStyle(Color.studioText3)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A resource editor's form: ``studioForm(measure:)``.
    func resourceEditorForm() -> some View {
        studioForm()
    }

    /// The old name of ``studioRowBackground()``, kept so in-flight
    /// branches still build. Use `studioRowBackground()`.
    func editorRowBackground() -> some View {
        studioRowBackground()
    }
}

/// A form section header: the native grouped-form header, so every
/// Form in the app (editors, Account, Workspace, Preferences) has one
/// header style with Dynamic Type metrics (DESIGN-REVIEW P1-7). Write it in
/// sentence case.
struct EditorSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }
}
