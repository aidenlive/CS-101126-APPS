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
                #if os(iOS)
                .keyboardType(.URL)
                .textContentType(.URL)
                #endif
        case .number:
            base
                #if os(iOS)
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
    /// The Studio look for a native grouped form: opaque Studio background,
    /// Studio body type and tint. Every in-app form uses it (editors,
    /// Account, Preferences, Workspace), so they all sit on the same page
    /// colour as the dashboards. The Mac Settings window keeps the system look.
    func studioForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .studioText(.ui)
            .tint(Color.studioAccentLine)
    }

    /// A resource editor's form: ``studioForm()``; give each section
    /// ``editorRowBackground()`` for Studio row surfaces.
    func resourceEditorForm() -> some View {
        studioForm()
    }

    /// Row surface for a section inside ``resourceEditorForm()``.
    func editorRowBackground() -> some View {
        listRowBackground(Color.studioSurface)
    }
}

/// A section header in Studio label type. Keep it to a few words: the
/// label style is uppercase.
struct EditorSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .studioText(.label)
            .foregroundStyle(Color.studioText3)
            .accessibilityAddTraits(.isHeader)
    }
}
