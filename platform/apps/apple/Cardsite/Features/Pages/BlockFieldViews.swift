import SwiftUI
import StudioKit
import CardsiteKit

/// One inspector row, rendered from the server's field spec. Every block
/// type is drawn by this one switch, as the web's BlockSettingsForm does.
struct BlockFieldView: View {
    let field: BlockField
    @Binding var value: JSONValue?
    let pageID: Int

    var body: some View {
        switch field.fieldKind {
        case .text:
            EditorFieldRow(label: field.label) {
                EditorTextInput(label: field.label, text: text)
            }
        case .url:
            EditorFieldRow(label: field.label) {
                EditorTextInput(label: field.label, text: text, prompt: "https://…")
                    .plainEntry()
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    #endif
            }
        case .textarea, .richText:
            // The web stores both as plain text (BlockSettingsForm draws a
            // textarea for `richtext`), so this is a multiline field.
            EditorFieldRow(label: field.label) {
                EditorTextInput(label: field.label, text: text, isMultiline: true)
            }
        case .code, .embed:
            EditorFieldRow(label: field.label) {
                EditorTextInput(label: field.label, text: text, isCode: true)
            }
        case .number:
            NumberFieldRow(label: field.label, value: $value)
        case .boolean:
            EditorToggleRow(label: field.label, isOn: Binding(
                get: { value?.boolValue ?? false },
                set: { value = .bool($0) }
            ))
        case .select:
            SelectFieldRow(label: field.label, options: field.options, value: $value)
        case .multiSelect:
            MultiSelectFieldRow(label: field.label, options: field.options, value: $value)
        case .color:
            ColorFieldRow(label: field.label, hex: Binding(
                get: { value?.stringValue.flatMap { $0.isEmpty ? nil : $0 } },
                set: { value = $0.map(JSONValue.string) }
            ))
        case .dateTime:
            DateTimeFieldRow(label: field.label, value: $value)
        case .timeZone:
            TimeZoneFieldRow(label: field.label, value: $value)
        case .image, .file:
            AssetFieldRow(label: field.label, imagesOnly: field.fieldKind == .image, text: text)
        case .structured:
            WebOnlyFieldRow(label: field.label, value: value, pageID: pageID)
        }
    }

    /// Strings in and out; an empty field removes the key.
    private var text: Binding<String> {
        Binding(
            get: { value?.displayString ?? "" },
            set: { value = $0.isEmpty ? nil : .string($0) }
        )
    }
}

// MARK: - Number

struct NumberFieldRow: View {
    let label: String
    @Binding var value: JSONValue?
    @State private var text = ""
    @State private var isInvalid = false

    var body: some View {
        EditorFieldRow(label: label, help: isInvalid ? String(localized: "Enter a number.") : nil) {
            EditorTextInput(label: label, text: $text)
                #if os(iOS) || os(visionOS)
                .keyboardType(.decimalPad)
                #endif
        }
        .onAppear { text = value?.displayString ?? "" }
        .onChange(of: text) { _, newText in
            let trimmed = newText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                isInvalid = false
                if value != nil { value = nil }
            } else if let parsed = Self.parse(trimmed) {
                isInvalid = false
                if value != parsed { value = parsed }
            } else {
                isInvalid = true
            }
        }
        .onChange(of: value) { _, newValue in
            // A revert or reload replaced the value: show it.
            if Self.parse(text.trimmingCharacters(in: .whitespaces)) != newValue {
                text = newValue?.displayString ?? ""
            }
        }
    }

    static func parse(_ text: String) -> JSONValue? {
        if let whole = Int(text) { return .int(whole) }
        if let decimal = Double(text.replacingOccurrences(of: ",", with: ".")), decimal.isFinite {
            return .double(decimal)
        }
        return nil
    }
}

// MARK: - Select

struct SelectFieldRow: View {
    let label: String
    let options: [BlockFieldOption]
    @Binding var value: JSONValue?

    var body: some View {
        let current = value?.displayString ?? ""
        Picker(selection: Binding(
            get: { current },
            set: { value = $0.isEmpty ? nil : .string($0) }
        )) {
            Text("Not set").tag("")
            ForEach(options) { option in
                Text(option.label).tag(option.value)
            }
            // A stored value the registry no longer lists stays visible
            // rather than silently reading as "Not set".
            if !current.isEmpty, !options.contains(where: { $0.value == current }) {
                Text(current).tag(current)
            }
        } label: {
            Text(label)
                .studioText(.ui)
                .foregroundStyle(Color.studioText)
        }
        .pickerStyle(.menu)
        .tint(Color.studioText2)
    }
}

struct MultiSelectFieldRow: View {
    let label: String
    let options: [BlockFieldOption]
    @Binding var value: JSONValue?
    @State private var isPicking = false

    private var selected: [String] {
        value?.arrayValue?.map(\.displayString).filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        EditorValueRow(label: label, value: summary) { isPicking = true }
            .sheet(isPresented: $isPicking) {
                OptionPickerSheet(
                    title: label,
                    options: options.map { PickerOption(value: $0.value, label: $0.label) },
                    selected: selected,
                    allowsMultiple: true
                ) { chosen in
                    value = chosen.isEmpty ? nil : .array(chosen.map(JSONValue.string))
                }
            }
    }

    private var summary: String {
        switch selected.count {
        case 0: return String(localized: "None")
        case 1: return options.first { $0.value == selected[0] }?.label ?? selected[0]
        default: return String(localized: "\(selected.count) selected")
        }
    }
}

// MARK: - Colour

/// A colour stored as `#rrggbb`. Unset means "the theme's default", which is
/// a real state, so it can be cleared back to it.
struct ColorFieldRow: View {
    let label: String
    @Binding var hex: String?

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            ColorPicker(selection: color, supportsOpacity: false) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(label)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                    Text(hex ?? String(localized: "Default"))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            if hex != nil {
                Button {
                    hex = nil
                } label: {
                    Label("Use Default", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Use the default \(label)"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var color: Binding<Color> {
        Binding(
            get: { hex.flatMap(HexColor.color(from:)) ?? Color.studioSurface3 },
            set: { newColor in
                let value = HexColor.hex(from: newColor)
                if value != hex { hex = value }
            }
        )
    }
}

// MARK: - Date and time zone

/// An instant, stored as RFC 3339 in UTC — what the web's DateTimePicker
/// writes (ADR-0040), so the countdown ends at one moment for every viewer.
struct DateTimeFieldRow: View {
    let label: String
    @Binding var value: JSONValue?

    var body: some View {
        if let date = value?.stringValue.flatMap(Self.parse) {
            HStack(spacing: StudioSpace.s3) {
                DatePicker(selection: Binding(
                    get: { date },
                    set: { value = .string($0.ISO8601Format()) }
                )) {
                    Text(label)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                }
                Button {
                    value = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear \(label)"))
            }
        } else {
            EditorValueRow(label: label, value: String(localized: "Not set")) {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                value = .string(tomorrow.ISO8601Format())
            }
        }
    }

    /// RFC 3339, or the zoneless `YYYY-MM-DDTHH:mm` older rows hold (read
    /// as local time, as the browser did).
    static func parse(_ raw: String) -> Date? {
        if let date = CardsiteJSON.parseTimestamp(raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

struct TimeZoneFieldRow: View {
    let label: String
    @Binding var value: JSONValue?
    @State private var isPicking = false

    var body: some View {
        let current = value?.stringValue ?? ""
        EditorValueRow(label: label, value: current.isEmpty ? String(localized: "Not set") : Self.display(current)) {
            isPicking = true
        }
        .sheet(isPresented: $isPicking) {
            OptionPickerSheet(
                title: label,
                options: TimeZone.knownTimeZoneIdentifiers.sorted().map { PickerOption(value: $0, label: Self.display($0)) },
                selected: current.isEmpty ? [] : [current],
                allowsMultiple: false
            ) { chosen in
                value = chosen.first.map(JSONValue.string)
            }
        }
    }

    static func display(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Assets

/// An address typed in, or chosen from the workspace's uploads. The text
/// field stays, because an asset hosted elsewhere is as valid as one here.
struct AssetFieldRow: View {
    let label: String
    let imagesOnly: Bool
    @Binding var text: String
    @State private var isPicking = false

    var body: some View {
        EditorFieldRow(label: label) {
            if imagesOnly, let url = URL(string: text), url.scheme != nil {
                AssetThumbnail(url: url)
            }
            EditorTextInput(label: label, text: $text, prompt: String(localized: "https://… or /uploads/…"))
                .plainEntry()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StudioSpace.s3) { actions }
                VStack(alignment: .leading, spacing: StudioSpace.s2) { actions }
            }
        }
        .sheet(isPresented: $isPicking) {
            UploadPickerSheet(imagesOnly: imagesOnly) { upload in
                text = upload.url
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            isPicking = true
        } label: {
            Label("Choose from Uploads", systemImage: imagesOnly ? "photo.on.rectangle" : "folder")
        }
        .buttonStyle(.borderless)
        if !text.isEmpty {
            Button(role: .destructive) {
                text = ""
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct AssetThumbnail: View {
    let url: URL
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 72

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .foregroundStyle(Color.studioText4)
            default:
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .background(Color.studioSurface3)
        .clipShape(RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Edited on the web

/// Structured fields (lists of items, opening hours, social links,
/// notification and payment pickers) are JSON on the web. The app does not
/// show raw JSON: it says what is set and hands off to the dashboard.
struct WebOnlyFieldRow: View {
    @Environment(AppModel.self) private var app
    let label: String
    let value: JSONValue?
    let pageID: Int

    var body: some View {
        EditorFieldRow(label: label, help: String(localized: "This part of the block is edited on the web. Everything else saves from here.")) {
            Text(summary)
                .studioText(.ui)
                .foregroundStyle(Color.studioText)
            Link(destination: app.configuration.bioPageEditorURL(pageID: pageID)) {
                Label("Edit on the Web", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
        }
    }

    private var summary: String {
        switch value {
        case .array(let items):
            if items.isEmpty { return String(localized: "Nothing added yet") }
            return items.count == 1 ? String(localized: "1 item") : String(localized: "\(items.count) items")
        case .object(let entries):
            let filled = entries.values.filter { !$0.isNull && $0 != .string("") }.count
            if filled == 0 { return String(localized: "Nothing added yet") }
            return filled == 1 ? String(localized: "1 entry") : String(localized: "\(filled) entries")
        case .string(let text) where !text.isEmpty:
            return String(localized: "Set")
        case .none, .null, .string:
            return String(localized: "Nothing added yet")
        default:
            return String(localized: "Set")
        }
    }
}
