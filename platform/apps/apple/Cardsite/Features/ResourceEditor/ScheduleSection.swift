import SwiftUI
import StudioKit

/*
 ScheduleSection — when a resource is live, and in which time zone.

     ScheduleSection(isScheduled: $form.isScheduled,
                     start: $form.start, end: $form.end,
                     timezone: $form.timezone,
                     canRemove: !original.isScheduled,
                     error: errors[.schedule])

 - The end can't be before the start: the end picker's range starts at the
   start, and moving the start past the end pulls the end along (ADR-0150).
 - Dates are absolute instants. The pickers show them in `timezone` (an IANA
   name, or "" for the device's zone) so the times read as the visitor's
   clock in that place.
 - `canRemove: false` keeps the switch on once a schedule is saved, for
   endpoints that can move a stored schedule but not clear it (short links:
   the server ignores `scheduled_at: null`). The footer says so.
 */
struct ScheduleSection: View {
    @Binding var isScheduled: Bool
    @Binding var start: Date
    @Binding var end: Date
    @Binding var timezone: String
    var canRemove: Bool = true
    var error: String?
    var title: String = String(localized: "Schedule")

    var body: some View {
        Section {
            Toggle(isOn: $isScheduled) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Scheduling")
                    Text("Live only between a start and an end.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .toggleStyle(.switch)
            .disabled(isScheduled && !canRemove)

            if isScheduled {
                DatePicker(selection: startBinding) {
                    Text("Start date")
                }
                DatePicker(selection: $end, in: start...) {
                    Text("End date")
                }
            }

            TimeZoneRow(identifier: $timezone)

            if let error {
                FormErrorText(message: error)
            }
        } header: {
            EditorSectionHeader(title)
        } footer: {
            if isScheduled, !canRemove {
                Text("A saved schedule can be moved but not removed yet.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .environment(\.timeZone, zone)
        .studioRowBackground()
    }

    /// Moving the start past the end pulls the end along.
    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { newStart in
                start = newStart
                if end < newStart { end = newStart }
            }
        )
    }

    private var zone: TimeZone {
        TimeZone(identifier: timezone) ?? .current
    }
}

/// The zone a resource's schedule and statistics read in.
private struct TimeZoneRow: View {
    @Binding var identifier: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            LabeledContent {
                HStack(spacing: StudioSpace.s1) {
                    Text(verbatim: TimeZonePickerSheet.title(for: identifier))
                        .studioText(.uiSm)
                        .foregroundStyle(identifier.isEmpty ? Color.studioText3 : Color.studioText2)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Color.studioText4)
                        .accessibilityHidden(true)
                }
            } label: {
                Text("Timezone").foregroundStyle(Color.studioText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            TimeZonePickerSheet(selection: $identifier)
        }
    }
}

/// A searchable list of IANA time zones, with "not set" first.
struct TimeZonePickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    row(identifier: "")
                }
                ForEach(filtered, id: \.self) { identifier in
                    row(identifier: identifier)
                }
                if filtered.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .searchable(text: $query, prompt: Text("Search time zones"))
            .navigationTitle("Timezone")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .cardsiteSheet(.form)
    }

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.identifiers }
        let needle = trimmed.replacingOccurrences(of: " ", with: "_")
        return Self.identifiers.filter {
            $0.localizedCaseInsensitiveContains(needle) || Self.title(for: $0).localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func row(identifier: String) -> some View {
        Button {
            selection = identifier
            dismiss()
        } label: {
            HStack {
                Text(verbatim: Self.title(for: identifier))
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                Spacer()
                if selection == identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.studioAccentLine)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.studioSurface)
        .accessibilityAddTraits(selection == identifier ? .isSelected : [])
    }

    /// "Europe/London (GMT+1)", or "Not set" for "".
    static func title(for identifier: String) -> String {
        guard !identifier.isEmpty else { return String(localized: "Not set") }
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let offset = zone.localizedName(for: .shortGeneric, locale: .current) ?? zone.abbreviation() ?? ""
        let name = identifier.replacingOccurrences(of: "_", with: " ")
        return offset.isEmpty ? name : "\(name) (\(offset))"
    }
}

#Preview("Schedule") {
    @Previewable @State var isScheduled = true
    @Previewable @State var start = Date.now
    @Previewable @State var end = Date.now.addingTimeInterval(7 * 86_400)
    @Previewable @State var timezone = "Europe/London"
    Form {
        ScheduleSection(isScheduled: $isScheduled, start: $start, end: $end, timezone: $timezone, canRemove: false)
    }
    .resourceEditorForm()
}
