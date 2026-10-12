import SwiftUI
import StudioKit
import CardsiteKit

/// Page Settings, with the web's sections: Page, SEO, Theme, Branding,
/// Display Rules and Pixels. (The web's Custom Code tab is a notice that the
/// feature doesn't exist yet, so it is left out here.) Controls the web
/// hides behind `bio_page_unwired_settings` are hidden the same way.
struct PageSettingsView: View {
    let editor: PageEditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var settings: PageSettingsModel? = nil

    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case page, seo, theme, branding, targeting, pixels
        var id: String { rawValue }

        var title: String {
            switch self {
            case .page: return String(localized: "Page")
            case .seo: return String(localized: "SEO")
            case .theme: return String(localized: "Theme")
            case .branding: return String(localized: "Branding")
            case .targeting: return String(localized: "Display Rules")
            case .pixels: return String(localized: "Pixels")
            }
        }

        var detail: String {
            switch self {
            case .page: return String(localized: "Name, bio, picture and address")
            case .seo: return String(localized: "How the page appears in search and shares")
            case .theme: return String(localized: "Background, colors, alignment and spacing")
            case .branding: return String(localized: "The branding bar at the foot of the page")
            case .targeting: return String(localized: "Who the page shows to")
            case .pixels: return String(localized: "Measurement pixels the page emits")
            }
        }

        var systemImage: String {
            switch self {
            case .page: return "person.crop.square"
            case .seo: return "magnifyingglass"
            case .theme: return "paintpalette"
            case .branding: return "seal"
            case .targeting: return "scope"
            case .pixels: return "dot.radiowaves.left.and.right"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    List {
                        Section {
                            ForEach(Pane.allCases) { section in
                                NavigationLink(value: section) {
                                    Label {
                                        VStack(alignment: .leading, spacing: StudioSpace.s1) {
                                            Text(section.title)
                                                .studioText(.ui)
                                                .foregroundStyle(Color.studioText)
                                            Text(section.detail)
                                                .studioText(.uiSm)
                                                .foregroundStyle(Color.studioText3)
                                        }
                                    } icon: {
                                        Image(systemName: section.systemImage)
                                            .foregroundStyle(Color.studioText2)
                                    }
                                    .padding(.vertical, StudioSpace.s1)
                                }
                            }
                        } footer: {
                            SettingsSaveStatus(settings: settings)
                        }
                        .studioRowBackground()
                    }
                    .studioList()
                    .navigationDestination(for: Pane.self) { section in
                        PageSettingsSectionView(section: section, settings: settings)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.studioBg)
            .navigationTitle("Page Settings")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await settings?.flush()
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            if settings == nil { settings = PageSettingsModel(editor: editor) }
        }
        .onDisappear {
            if let settings { Task { await settings.flush() } }
        }
        .cardsiteSheet(.form)
    }
}

/// "Saving…", the last error, or how saving works.
private struct SettingsSaveStatus: View {
    let settings: PageSettingsModel

    var body: some View {
        if let error = settings.saveError {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioError)
        } else if settings.isSaving {
            Text("Saving…")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        } else {
            Text("Changes save as you go.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
    }
}

// MARK: - Sections

struct PageSettingsSectionView: View {
    @Environment(PagesModel.self) private var pages
    let section: PageSettingsView.Pane
    let settings: PageSettingsModel

    var body: some View {
        Group {
            switch section {
            case .page: PageSection(settings: settings, showUnwired: showUnwired)
            case .seo: SEOSection(settings: settings)
            case .theme: ThemeSection(settings: settings, showUnwired: showUnwired)
            case .branding: BrandingSection(settings: settings, showUnwired: showUnwired)
            case .targeting: DisplayRulesForm(editor: settings.editor)
            case .pixels: PixelsForm(editor: settings.editor)
            }
        }
        .studioForm()
        .navigationTitle(section.title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear {
            Task { await settings.flush() }
        }
    }

    private var showUnwired: Bool { pages.isFlagOn(PagesModel.Flag.unwiredSettings) }
}

/// Bindings into the settings draft.
private extension PageSettingsModel {
    func text(_ key: String) -> Binding<String> {
        Binding(
            get: { self.string(key) },
            set: { self.set(key, $0.isEmpty ? nil : .string($0)) }
        )
    }

    func toggle(_ key: String, default fallback: Bool = false) -> Binding<Bool> {
        Binding(
            get: { self.bool(key, default: fallback) },
            set: { self.set(key, .bool($0), immediately: true) }
        )
    }

    func hex(_ key: String) -> Binding<String?> {
        Binding(
            get: { self.value(key)?.stringValue.flatMap { $0.isEmpty ? nil : $0 } },
            set: { self.set(key, $0.map(JSONValue.string)) }
        )
    }

    func choice(_ key: String, default fallback: String) -> Binding<String> {
        Binding(
            get: { self.value(key)?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? fallback },
            set: { self.set(key, .string($0), immediately: true) }
        )
    }

}

private struct PageSection: View {
    @Environment(AppModel.self) private var app
    let settings: PageSettingsModel
    let showUnwired: Bool

    @State private var slug = ""
    @State private var slugError: String? = nil
    @State private var isChangingSlug = false

    var body: some View {
        Form {
            Section {
                EditorFieldRow(label: String(localized: "Name"), help: String(localized: "Shown at the top of the page.")) {
                    EditorTextInput(label: String(localized: "Name"), text: settings.text("title"))
                }
                EditorFieldRow(label: String(localized: "Bio"), help: String(localized: "One or two lines under the name.")) {
                    EditorTextInput(label: String(localized: "Bio"), text: settings.text("description"), isMultiline: true)
                }
                AssetFieldRow(label: String(localized: "Picture"), imagesOnly: true, text: settings.text("image"))
            }
            .studioRowBackground()
            Section {
                EditorFieldRow(
                    label: String(localized: "Address"),
                    help: slugError ?? app.addresses.display(for: slug.isEmpty ? "…" : slug)
                ) {
                    EditorTextInput(label: String(localized: "Address"), text: $slug, prompt: "my-bio")
                        .plainEntry()
                        .onSubmit { Task { await changeSlug() } }
                    if let current = settings.editor.page?.slug, slug != current {
                        HStack(spacing: StudioSpace.s3) {
                            Button {
                                Task { await changeSlug() }
                            } label: {
                                if isChangingSlug {
                                    ProgressView()
                                } else {
                                    Text("Change Address")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.studioAccentLine)
                            .disabled(isChangingSlug)
                            Button("Cancel") {
                                slug = current
                                slugError = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } footer: {
                Text("Changing the address frees the old one. Anything printed or shared with it stops working.")
            }
            .studioRowBackground()
            Section {
                EditorToggleRow(label: String(localized: "Sensitive content warning"),
                                isOn: settings.toggle("sensitive_content"))
                EditorToggleRow(
                    label: String(localized: "Show in directory"),
                    isOn: Binding(
                        get: { settings.editor.page?.directoryIsEnabled ?? true },
                        set: { isOn in Task { await settings.setListedInDirectory(isOn) } }
                    )
                )
                if showUnwired {
                    EditorToggleRow(label: String(localized: "Show share buttons"), isOn: settings.toggle("share_is_enabled"))
                    EditorToggleRow(label: String(localized: "Enable leap link (skip countdown)"), isOn: settings.toggle("leap_link"))
                    EditorToggleRow(label: String(localized: "Scroll buttons"), isOn: settings.toggle("scroll_buttons_is_enabled"))
                }
            }
            .studioRowBackground()
            Section { SettingsSaveStatus(settings: settings) }
            .studioRowBackground()
        }
        .onAppear { slug = settings.editor.page?.slug ?? "" }
        .onChange(of: slug) { slugError = nil }
    }

    private func changeSlug() async {
        guard let current = settings.editor.page?.slug, slug != current, !isChangingSlug else { return }
        isChangingSlug = true
        defer { isChangingSlug = false }
        if let message = await settings.changeSlug(to: slug) {
            slugError = message
        } else {
            Haptics.success()
        }
    }
}

private struct SEOSection: View {
    let settings: PageSettingsModel

    var body: some View {
        Form {
            Section {
                EditorFieldRow(label: String(localized: "SEO title")) {
                    EditorTextInput(label: String(localized: "SEO title"), text: settings.text("seo_title"),
                                    prompt: String(localized: "My bio page"))
                }
                EditorFieldRow(label: String(localized: "Meta description")) {
                    EditorTextInput(label: String(localized: "Meta description"), text: settings.text("seo_meta_description"),
                                    prompt: String(localized: "Describe your bio page…"), isMultiline: true)
                }
                EditorFieldRow(label: String(localized: "Meta keywords")) {
                    EditorTextInput(label: String(localized: "Meta keywords"), text: settings.text("seo_meta_keywords"),
                                    prompt: String(localized: "comma, separated, keywords"))
                }
            }
            .studioRowBackground()
            Section { SettingsSaveStatus(settings: settings) }
            .studioRowBackground()
        }
    }
}

private struct ThemeSection: View {
    let settings: PageSettingsModel
    let showUnwired: Bool

    var body: some View {
        let background = settings.choice("background_type", default: "color")
        Form {
            Section {
                Picker(selection: background) {
                    Text("Solid color").tag("color")
                    Text("Gradient").tag("gradient")
                    Text("Image").tag("image")
                } label: {
                    Text("Background").studioText(.ui)
                }
                .pickerStyle(.menu)
                switch background.wrappedValue {
                case "gradient":
                    ColorFieldRow(label: String(localized: "Color 1"), hex: settings.hex("background_color_one"))
                    ColorFieldRow(label: String(localized: "Color 2"), hex: settings.hex("background_color_two"))
                case "image":
                    AssetFieldRow(label: String(localized: "Background image"), imagesOnly: true, text: settings.text("background"))
                default:
                    ColorFieldRow(label: String(localized: "Background color"), hex: settings.hex("background_color"))
                }
            } header: {
                Text("Background")
            }
            .studioRowBackground()
            Section {
                ColorFieldRow(label: String(localized: "Text color"), hex: settings.hex("text_color"))
                ColorFieldRow(label: String(localized: "Button color"), hex: settings.hex("btn_background_color"))
                ColorFieldRow(label: String(localized: "Button text color"), hex: settings.hex("btn_text_color"))
            } header: {
                Text("Colors")
            }
            .studioRowBackground()
            Section {
                Picker(selection: settings.choice("text_alignment", default: "center")) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                } label: {
                    Text("Text alignment").studioText(.ui)
                }
                .pickerStyle(.menu)
                SettingStepperRow(label: String(localized: "Font size"), key: "font_size", range: 12...24, fallback: 16, settings: settings)
                SettingStepperRow(label: String(localized: "Block spacing"), key: "block_spacing", range: 0...48, fallback: 8, settings: settings)
                SettingStepperRow(label: String(localized: "Corner radius"), key: "border_radius", range: 0...48, fallback: 8, settings: settings)
            } header: {
                Text("Layout")
            }
            .studioRowBackground()
            if showUnwired {
                Section {
                    Picker(selection: settings.choice("font", default: "")) {
                        Text("Default").tag("")
                        ForEach(["Inter", "Epilogue", "Poppins", "Roboto", "Lato", "Open Sans", "Montserrat"], id: \.self) { font in
                            Text(verbatim: font).tag(font)
                        }
                    } label: {
                        Text("Font").studioText(.ui)
                    }
                    animationPicker(String(localized: "Block animation"), key: "animation")
                    animationPicker(String(localized: "Hover animation"), key: "hover_animation")
                } header: {
                    Text("Type and motion")
                }
                .studioRowBackground()
            }
            Section { SettingsSaveStatus(settings: settings) }
            .studioRowBackground()
        }
    }

    private func animationPicker(_ label: String, key: String) -> some View {
        Picker(selection: settings.choice(key, default: "")) {
            Text("None").tag("")
            Text("Fade").tag("fade")
            Text("Slide").tag("slide")
            Text("Zoom").tag("zoom")
            Text("Bounce").tag("bounce")
        } label: {
            Text(label).studioText(.ui)
        }
    }
}

/// A whole number in pixels with a range, where unset means the theme's
/// default (shown, and restorable).
private struct SettingStepperRow: View {
    let label: String
    let key: String
    let range: ClosedRange<Int>
    let fallback: Int
    let settings: PageSettingsModel

    var body: some View {
        let current = settings.int(key)
        HStack(spacing: StudioSpace.s3) {
            Stepper(value: Binding(
                get: { min(max(current ?? fallback, range.lowerBound), range.upperBound) },
                set: { settings.set(key, .int($0)) }
            ), in: range) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(label)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                    Text(current.map { String(localized: "\($0) px") } ?? String(localized: "Default (\(fallback) px)"))
                        .studioText(.uiSm)
                        .monospacedDigit()
                        .foregroundStyle(Color.studioText3)
                }
            }
            if current != nil {
                Button {
                    settings.set(key, nil, immediately: true)
                } label: {
                    Label("Use Default", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Use the default \(label)"))
            }
        }
    }
}

private struct BrandingSection: View {
    let settings: PageSettingsModel
    let showUnwired: Bool

    var body: some View {
        Form {
            Section {
                EditorToggleRow(label: String(localized: "Show branding bar"),
                                isOn: settings.toggle("display_branding", default: true))
                EditorFieldRow(label: String(localized: "Branding name")) {
                    EditorTextInput(label: String(localized: "Branding name"), text: settings.text("branding_name"),
                                    prompt: String(localized: "Powered by Cardsite"))
                }
                EditorFieldRow(label: String(localized: "Branding URL")) {
                    EditorTextInput(label: String(localized: "Branding URL"), text: settings.text("branding_url"),
                                    prompt: "https://…")
                        .plainEntry()
                        #if os(iOS) || os(visionOS)
                        .keyboardType(.URL)
                        #endif
                }
            }
            .studioRowBackground()
            if showUnwired {
                Section {
                    EditorToggleRow(label: String(localized: "Branded button"),
                                    isOn: settings.toggle("branded_button_is_enabled"))
                    if settings.bool("branded_button_is_enabled") {
                        EditorFieldRow(label: String(localized: "Button title")) {
                            EditorTextInput(label: String(localized: "Button title"), text: settings.text("branded_button_title"))
                        }
                        EditorFieldRow(label: String(localized: "Button subtitle")) {
                            EditorTextInput(label: String(localized: "Button subtitle"), text: settings.text("branded_button_content"))
                        }
                    }
                }
                .studioRowBackground()
            }
            Section { SettingsSaveStatus(settings: settings) }
            .studioRowBackground()
        }
    }
}
