import SwiftUI
import StudioKit
import CardsiteKit

/// One builder field as a native form row, bound to the draft.
struct QRFieldRow: View {
    let field: QRField
    @Binding var draft: QRCodeDraft

    var body: some View {
        switch field.kind {
        case .text(let entry):
            QRTextRow(label: field.label, placeholder: field.placeholder, help: field.help,
                      text: text, entry: entry)
        case .multiline(let lines):
            QRTextRow(label: field.label, placeholder: field.placeholder, help: field.help,
                      text: text, axis: .vertical, lines: lines)
        case .choice(let options):
            Picker(field.label, selection: text) {
                ForEach(options) { option in
                    Text(verbatim: option.label).tag(option.value)
                }
            }
        case .toggle:
            Toggle(field.label, isOn: Binding(
                get: { draft.text(for: field) == "true" },
                set: { draft.setText($0 ? "true" : "false", for: field) }
            ))
        case .dateTime:
            QRDateTimeRow(label: field.label, text: text)
        }
    }

    private var text: Binding<String> {
        Binding(
            get: { draft.text(for: field) },
            set: { draft.setText($0, for: field) }
        )
    }
}

/// A labelled text field. On iPhone and iPad the label sits above the field,
/// since a grouped form otherwise shows only the prompt and the label is
/// lost once something is typed. On Mac the form puts it beside the field.
struct QRTextRow: View {
    let label: String
    var placeholder: String = ""
    var help: String?
    @Binding var text: String
    var entry: QRField.Entry?
    var axis: Axis = .horizontal
    var lines: Int = 1
    var error: String?

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            field
            footnote
        }
        #else
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            Text(label)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .accessibilityHidden(true)
            field
                .studioText(.body)
            footnote
        }
        .padding(.vertical, StudioSpace.s1)
        #endif
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(text: $text, prompt: placeholder.isEmpty ? nil : Text(verbatim: placeholder), axis: axis) {
            Text(label)
        }
        .lineLimit(axis == .vertical ? lines...max(lines, 8) : 1...1)
        .accessibilityLabel(Text(label))
        if let entry {
            base.qrEntry(entry)
        } else {
            base
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioError)
        } else if let help {
            Text(help)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
    }
}

extension View {
    /// Keyboard, autofill and correction for a kind of entry.
    @ViewBuilder
    func qrEntry(_ entry: QRField.Entry) -> some View {
        #if os(iOS)
        switch entry {
        case .words:
            self
        case .personName(let part):
            self.textContentType(part == .given ? .givenName : .familyName)
                .textInputAutocapitalization(.words)
        case .code:
            self.plainEntry()
        case .email:
            self.plainEntry().keyboardType(.emailAddress).textContentType(.emailAddress)
        case .phone:
            self.plainEntry().keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .url:
            self.plainEntry().keyboardType(.URL).textContentType(.URL)
        case .decimal:
            self.plainEntry().keyboardType(.decimalPad)
        case .signedDecimal:
            // decimalPad has no minus key.
            self.plainEntry().keyboardType(.numbersAndPunctuation)
        }
        #else
        switch entry {
        case .words, .personName:
            self
        case .code, .email, .phone, .url, .decimal, .signedDecimal:
            self.plainEntry()
        }
        #endif
    }
}

/// An optional floating date and time: off sends "", on shows a picker.
struct QRDateTimeRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { !text.isEmpty },
            set: { isOn in
                text = isOn ? QRFloatingTime.string(QRFloatingTime.nextHour()) : ""
            }
        ))
        if let date = QRFloatingTime.date(text) {
            DatePicker(
                selection: Binding(get: { date }, set: { text = QRFloatingTime.string($0) }),
                displayedComponents: [.date, .hourAndMinute]
            ) {
                Text(label)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !text.isEmpty {
            // A value the form can't read (typed elsewhere): keep it visible.
            LabeledContent(label) { Text(verbatim: text).studioText(.mono) }
        }
    }
}

// MARK: - Type picker

/// The type control. iPhone gets a searchable sheet with a section per
/// group; iPad and Mac get a menu with the same sections.
struct QRTypePicker: View {
    let types: [QRCodeTypeInfo]
    let selection: String
    let label: String
    let select: (String) -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var isPresentingSheet = false

    var body: some View {
        #if os(iOS)
        if sizeClass == .compact {
            sheetButton
        } else {
            menu
        }
        #else
        menu
        #endif
    }

    private var menu: some View {
        Picker(selection: Binding(get: { selection }, set: select)) {
            if !types.contains(where: { $0.value == selection }) {
                Label(label, systemImage: QRCodeCatalog.symbol(for: selection)).tag(selection)
            }
            ForEach(QRCodeCatalog.grouped(types), id: \.group) { group in
                Section(QRCodeCatalog.groupTitle(group.group)) {
                    ForEach(group.types) { info in
                        Label(info.label, systemImage: QRCodeCatalog.symbol(for: info.value)).tag(info.value)
                    }
                }
            }
        } label: {
            Text("Type")
        }
        .pickerStyle(.menu)
    }

    private var sheetButton: some View {
        Button {
            isPresentingSheet = true
        } label: {
            LabeledContent {
                HStack(spacing: StudioSpace.s2) {
                    Label(label, systemImage: QRCodeCatalog.symbol(for: selection))
                        .foregroundStyle(Color.studioText2)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.studioText4)
                        .accessibilityHidden(true)
                }
            } label: {
                Text("Type").foregroundStyle(Color.studioText)
            }
        }
        .accessibilityValue(Text(label))
        .accessibilityHint(Text("Shows all QR code types"))
        .sheet(isPresented: $isPresentingSheet) {
            QRTypeSheet(types: types, selection: selection) { value in
                select(value)
                isPresentingSheet = false
            }
        }
    }
}

/// Every type in sections by group, with search.
struct QRTypeSheet: View {
    let types: [QRCodeTypeInfo]
    let selection: String
    let select: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let groups = QRCodeCatalog.grouped(filtered)
                if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.group) { group in
                    Section(QRCodeCatalog.groupTitle(group.group)) {
                        ForEach(group.types) { info in
                            Button {
                                select(info.value)
                            } label: {
                                HStack(spacing: StudioSpace.s3) {
                                    Image(systemName: QRCodeCatalog.symbol(for: info.value))
                                        .foregroundStyle(Color.studioText2)
                                        .frame(minWidth: StudioSpace.s6)
                                        .accessibilityHidden(true)
                                    Text(info.label)
                                        .studioText(.body)
                                        .foregroundStyle(Color.studioText)
                                    Spacer(minLength: StudioSpace.s2)
                                    if info.value == selection {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.studioAccentLine)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(info.value == selection ? .isSelected : [])
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Search types"))
            .navigationTitle("QR Code Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filtered: [QRCodeTypeInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return types }
        return types.filter {
            $0.label.localizedCaseInsensitiveContains(trimmed)
                || QRCodeCatalog.groupTitle($0.group).localizedCaseInsensitiveContains(trimmed)
        }
    }
}
