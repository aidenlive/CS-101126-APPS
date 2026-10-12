import SwiftUI
import StudioKit
import CardsiteKit

// Building blocks shared by the block inspector and Page Settings, so both
// forms have one row anatomy and one rhythm.

/// A label stacked above its control. Stacking (rather than label-left)
/// keeps rows readable at the largest text sizes.
struct EditorFieldRow<Content: View>: View {
    let label: String
    var help: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Text(label)
                .studioText(.uiSm)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText2)
            content()
            if let help {
                Text(help)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .contain)
    }
}

/// A row that shows a current value and opens a chooser.
struct EditorValueRow: View {
    let label: String
    let value: String
    var isDisabled = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s1))
                : AnyLayout(HStackLayout(spacing: StudioSpace.s3))
            layout {
                Text(label)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                if !typeSize.isAccessibilitySize { Spacer(minLength: StudioSpace.s2) }
                HStack(spacing: StudioSpace.s1) {
                    Text(value)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Color.studioText4)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A Studio-styled switch row inside a Form.
struct EditorToggleRow: View {
    let label: String
    var help: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(label)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                if let help {
                    Text(help)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.studioAccent)
    }
}

/// A plain, Studio-typed text input for use inside a Form row.
struct EditorTextInput: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    var isMultiline = false
    var isCode = false

    var body: some View {
        Group {
            if isMultiline || isCode {
                TextField(label, text: $text, prompt: prompt.map { Text($0) }, axis: .vertical)
                    .lineLimit(isCode ? 4...16 : 3...12)
            } else {
                TextField(label, text: $text, prompt: prompt.map { Text($0) })
            }
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .modifier(EditorInputFont(isCode: isCode))
        .padding(.horizontal, StudioSpace.s3)
        .padding(.vertical, StudioSpace.s2)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                .fill(Color.studioSurface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
        )
        .accessibilityLabel(label)
    }
}

private struct EditorInputFont: ViewModifier {
    let isCode: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCode {
            // Code and embed snippets need a true monospaced face; the
            // Studio "mono" style is a grotesk. The text style keeps
            // Dynamic Type.
            content
                .font(.callout.monospaced())
                .foregroundStyle(Color.studioText)
                .plainEntry()
        } else {
            content
                .studioText(.ui)
                .foregroundStyle(Color.studioText)
        }
    }
}

// MARK: - Option picker

/// One choice in an ``OptionPickerSheet``.
struct PickerOption: Identifiable, Hashable, Sendable {
    let value: String
    let label: String
    var id: String { value }
}

/// A searchable list of choices, single or multiple, for long vocabularies
/// (time zones, countries, languages) and multi-select fields.
struct OptionPickerSheet: View {
    let title: String
    let options: [PickerOption]
    let allowsMultiple: Bool
    let onDone: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String]
    @State private var query = ""

    init(title: String, options: [PickerOption], selected: [String], allowsMultiple: Bool,
         onDone: @escaping ([String]) -> Void) {
        self.title = title
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.onDone = onDone
        _selection = State(initialValue: selected)
    }

    private var filtered: [PickerOption] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(trimmed) || $0.value.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowSeparator(.hidden)
                }
                ForEach(filtered) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: StudioSpace.s3) {
                            Text(option.label)
                                .studioText(.ui)
                                .foregroundStyle(Color.studioText)
                            Spacer(minLength: StudioSpace.s2)
                            if selection.contains(option.value) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.studioAccentLine)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(option.value) ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .searchable(text: $query, prompt: Text("Search"))
            .navigationTitle(title)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDone(selection)
                            dismiss()
                        }
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear All") { selection = [] }
                            .disabled(selection.isEmpty)
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button("Clear All") { selection = [] }
                            .disabled(selection.isEmpty)
                    }
                    #endif
                } else if !selection.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            onDone([])
                            dismiss()
                        }
                    }
                }
            }
        }
        .cardsiteSheet(.form)
    }

    private func choose(_ option: PickerOption) {
        if allowsMultiple {
            // The author's order is kept: a new pick appends.
            if let index = selection.firstIndex(of: option.value) {
                selection.remove(at: index)
            } else {
                selection.append(option.value)
            }
        } else {
            onDone([option.value])
            dismiss()
        }
    }
}

// MARK: - Web hand-off

/// The dashboard's own editor for a bio page, for what the app shows read-only.
extension AppConfiguration {
    func bioPageEditorURL(pageID: Int) -> URL {
        webURL.appendingPathComponent("biolinks/\(pageID)")
    }
}
