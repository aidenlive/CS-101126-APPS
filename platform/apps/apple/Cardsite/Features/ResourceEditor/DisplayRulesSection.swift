import SwiftUI
import StudioKit
import CardsiteKit

/*
 DisplayRulesSection — audience targeting as a Form section.

 Six rows (countries, continents, browsers, operating systems, device types,
 languages). Each opens a searchable multi-select sheet over the server's
 own vocabulary (`GET /reference/targeting`), so the app can never offer a
 value the matcher can't match.

     DisplayRulesSection(rules: $form.displayRules,
                         options: options.targeting.value,
                         loadFailed: options.targeting.error != nil,
                         isLocked: !options.allowsTargeting,
                         error: errors[.targeting])

 - `isLocked` (the plan lacks `targeting_is_enabled`): the rows become
   read-only and say so. Rules already set can still be removed, because
   the server lets any plan clear targeting.
 - `loadFailed` with no options: the rows are read-only and the stored
   rules are kept exactly as they are (the web's wording).
 - Values stored that the vocabulary doesn't list are shown by their raw
   value and kept until the user removes them.
 - Send the rules only when they changed (`LinkChanges.displayRules`), so
   saving an untouched resource never trips the targeting gate.
 */
struct DisplayRulesSection: View {
    @Binding var rules: DisplayRules
    let options: TargetingOptions?
    var loadFailed: Bool = false
    var isLocked: Bool = false
    var error: String?
    var title: String = String(localized: "Targeting rules")

    var body: some View {
        Section {
            if isLocked {
                LockedFeatureNote(message: String(localized: "Audience targeting isn’t included in your plan."))
            } else if options == nil, loadFailed {
                LockedFeatureNote(message: String(localized: "Targeting options couldn’t be loaded, so the pickers are unavailable. Any rules already set here are preserved and will be saved unchanged."))
            }
            ForEach(DisplayRules.Dimension.allCases) { dimension in
                DisplayRuleRow(
                    dimension: dimension,
                    selection: Binding(get: { rules[dimension] }, set: { rules[dimension] = $0 }),
                    options: options?.options(for: dimension),
                    isEditable: !isLocked && options != nil
                )
            }
            if isLocked, rules.narrowsAudience {
                Button(role: .destructive) {
                    rules = DisplayRules(other: rules.other.filter { $0.key != "cities" })
                } label: {
                    Text("Remove all targeting rules")
                }
            }
            if let error {
                FormErrorText(message: error)
            }
        } header: {
            EditorSectionHeader(title)
        } footer: {
            Text("Leave a dimension empty to show this to everyone.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .editorRowBackground()
    }
}

extension DisplayRules.Dimension {
    var title: String {
        switch self {
        case .countries: return String(localized: "Countries")
        case .continents: return String(localized: "Continents")
        case .browsers: return String(localized: "Browsers")
        case .operatingSystems: return String(localized: "Operating Systems")
        case .deviceTypes: return String(localized: "Device Types")
        case .languages: return String(localized: "Languages")
        }
    }

    /// Shown when nothing is selected.
    var everyone: String {
        switch self {
        case .countries: return String(localized: "All countries")
        case .continents: return String(localized: "All continents")
        case .browsers: return String(localized: "All browsers")
        case .operatingSystems: return String(localized: "All OS")
        case .deviceTypes: return String(localized: "All devices")
        case .languages: return String(localized: "All languages")
        }
    }

    var systemImage: String {
        switch self {
        case .countries: return "flag"
        case .continents: return "globe.europe.africa"
        case .browsers: return "safari"
        case .operatingSystems: return "desktopcomputer"
        case .deviceTypes: return "iphone"
        case .languages: return "character.bubble"
        }
    }
}

/// One dimension: its summary, and the sheet that edits it.
private struct DisplayRuleRow: View {
    let dimension: DisplayRules.Dimension
    @Binding var selection: [String]
    let options: [TargetingOption]?
    let isEditable: Bool

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            LabeledContent {
                HStack(spacing: StudioSpace.s1) {
                    Text(summary)
                        .studioText(.uiSm)
                        .foregroundStyle(selection.isEmpty ? Color.studioText3 : Color.studioText2)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    if isEditable {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(Color.studioText4)
                            .accessibilityHidden(true)
                    }
                }
            } label: {
                Label(dimension.title, systemImage: dimension.systemImage)
                    .foregroundStyle(Color.studioText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityHint(isEditable ? Text("Choose who sees this") : Text(""))
        .sheet(isPresented: $isPresented) {
            MultiSelectSheet(title: dimension.title, options: options ?? [], selection: $selection)
        }
    }

    private var summary: String {
        guard !selection.isEmpty else { return dimension.everyone }
        let labels = selection.map { value in options?.first(where: { $0.value == value })?.label ?? value }
        if labels.count <= 2 { return labels.formatted(.list(type: .and)) }
        return String(localized: "\(labels[0]) and \(labels.count - 1) more")
    }
}

/// A searchable list of options with checkmarks. Keeps the order things
/// were picked in, and lists the picked ones first.
struct MultiSelectSheet: View {
    let title: String
    let options: [TargetingOption]
    @Binding var selection: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !selection.isEmpty {
                    Section {
                        ForEach(selection, id: \.self) { value in
                            row(value: value, label: label(for: value))
                        }
                    } header: {
                        EditorSectionHeader(String(localized: "Selected"))
                    }
                    .editorRowBackground()
                }
                Section {
                    ForEach(filtered) { option in
                        row(value: option.value, label: option.label)
                    }
                    if filtered.isEmpty, !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    if query.isEmpty, !selection.isEmpty {
                        EditorSectionHeader(String(localized: "All"))
                    }
                }
                .editorRowBackground()
            }
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .searchable(text: $query, prompt: Text("Search \(title.lowercased())"))
            .navigationTitle(title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !selection.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { selection = [] }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private var filtered: [TargetingOption] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(trimmed) || $0.value.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func label(for value: String) -> String {
        options.first(where: { $0.value == value })?.label ?? value
    }

    private func row(value: String, label: String) -> some View {
        let isSelected = selection.contains(value)
        return Button {
            if isSelected {
                selection.removeAll { $0 == value }
            } else {
                selection.append(value)
            }
        } label: {
            HStack {
                Text(verbatim: label)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.studioAccentLine)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Display rules") {
    @Previewable @State var rules = DisplayRules([.countries: ["GB", "US"], .deviceTypes: ["mobile"]])
    Form {
        DisplayRulesSection(rules: $rules, options: .preview)
        DisplayRulesSection(rules: $rules, options: .preview, isLocked: true, title: "Locked")
    }
    .resourceEditorForm()
}

extension TargetingOptions {
    /// A few of each, for previews.
    static let preview = TargetingOptions(
        browsers: [.init(value: "chrome", label: "Chrome"), .init(value: "safari", label: "Safari")],
        continents: [.init(value: "EU", label: "Europe"), .init(value: "NA", label: "North America")],
        countries: [.init(value: "GB", label: "United Kingdom"), .init(value: "US", label: "United States"),
                    .init(value: "FR", label: "France")],
        deviceTypes: [.init(value: "mobile", label: "Mobile"), .init(value: "tablet", label: "Tablet"),
                      .init(value: "desktop", label: "Desktop")],
        languages: [.init(value: "en", label: "English"), .init(value: "fr", label: "French")],
        operatingSystems: [.init(value: "ios", label: "iOS"), .init(value: "android", label: "Android")]
    )
}
