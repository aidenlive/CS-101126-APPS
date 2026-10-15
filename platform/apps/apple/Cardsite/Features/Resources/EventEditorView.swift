import SwiftUI
import UniformTypeIdentifiers
import StudioKit
import CardsiteKit

/// Everything the event editor edits. Start and end stay wall-clock strings
/// (`YYYY-MM-DDTHH:mm`) so changing the time zone keeps the time the author
/// typed, as the web stores it (ADR-0101).
struct EventForm: Equatable {
    var address: AddressForm
    var event: EventSettings
    var gate: GateForm

    init(now: Date = .now) {
        address = AddressForm()
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        event = EventSettings(start: EventWallClock.string(from: start, timezone: zone.identifier),
                              end: EventWallClock.string(from: start.addingTimeInterval(3 * 3_600), timezone: zone.identifier),
                              timezone: zone.identifier)
        gate = GateForm()
    }

    init(resource: ManagedResource) {
        address = AddressForm(slug: resource.slug, domainID: resource.domainID)
        event = resource.event
        gate = GateForm(gate: resource.gate)
    }

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        address.validate(into: &errors)
        if event.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.name] = String(localized: "An event name is required.")
        }
        let start = event.startDate
        if start == nil {
            errors[.start] = String(localized: "Choose when the event starts.")
        }
        if let start, let end = event.endDate, end < start {
            errors[.end] = String(localized: "The end can’t be before the start.")
        } else if event.endDate == nil {
            errors[.end] = String(localized: "Choose when the event ends.")
        }
        let url = event.url.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty, Destination.normalized(url) == nil {
            errors[.eventURL] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        }
        gate.validate(into: &errors)
        return errors
    }

    var draft: EventDraft {
        var event = self.event
        let url = event.url.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty { event.url = Destination.normalized(url)?.absoluteString ?? url }
        return EventDraft(slug: address.trimmedSlug, domainID: address.domainID, event: event,
                          gate: gate.gate, password: gate.password)
    }
}

/// An event: name, place, web page, start and end in the event's own time
/// zone, a note, and the gate, with a live preview. Saved events also offer
/// Add to Calendar (iOS) or the `.ics` (Mac).
struct EventEditorView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ResourceEditorModel<EventForm>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    @State private var isAddingToCalendar = false
    @State private var isPickingZone = false

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: EventForm(),
            list: list,
            makeForm: { item in item.link.map(EventForm.init(resource:)) ?? EventForm() },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let item {
                    return .link(try await client.updateEvent(id: item.id, form.draft))
                }
                return .link(try await client.createEvent(form.draft))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .event, model: model, list: list, onCreated: onCreated) { item in
            if let resource = item.link {
                heroAction(for: resource)
            }
        } fields: {
            Section {
                EventPreviewCard(event: model.form.event)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                EditorSectionHeader(String(localized: "Preview"))
            } footer: {
                Text("The event page as visitors see it, in the event’s own time zone.")
            }

            Section {
                ResourceAddressRows(kind: .event, address: $model.form.address, list: list, isNew: model.isNew,
                                    savedAddress: model.savedForm.address, error: model.errors[.slug],
                                    prompt: String(localized: "summer-launch"))
            } header: {
                EditorSectionHeader(String(localized: "Address"))
            } footer: {
                ResourceAddressFooter(list: list, isNew: model.isNew)
            }
            .studioRowBackground()

            Section {
                EditorTextField(String(localized: "Event Name"), text: $model.form.event.name,
                                prompt: String(localized: "My Event"), error: model.errors[.name])
                EditorTextField(String(localized: "Location"), text: $model.form.event.location,
                                prompt: String(localized: "Event venue or address"))
                    #if os(iOS) || os(visionOS)
                    .textContentType(.fullStreetAddress)
                    #endif
                EditorTextField(String(localized: "Event URL"), text: $model.form.event.url,
                                prompt: "https://example.com/tickets", kind: .url,
                                help: String(localized: "A page with more about the event, such as tickets or a stream."),
                                error: model.errors[.eventURL])
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Note")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .accessibilityHidden(true)
                    TextField(String(localized: "Note"), text: $model.form.event.note,
                              prompt: Text("Optional event description"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...6)
                        .studioText(.ui)
                }
                .padding(.vertical, StudioSpace.s1)
            } header: {
                EditorSectionHeader(String(localized: "Details"))
            }
            .studioRowBackground()

            whenSection($model.form.event)

            GatingSection(
                password: $model.form.gate.password,
                hasPassword: model.savedForm.gate.hasPassword,
                clicksLimit: $model.form.gate.clicksLimitText,
                expirationURL: $model.form.gate.expirationURL,
                sensitiveContent: $model.form.gate.sensitiveContent,
                passwordLocked: !list.options.allowsPasswordProtection,
                errors: .init(password: model.errors[.password], clicksLimit: model.errors[.clicksLimit],
                              expirationURL: model.errors[.expirationURL])
            )
        }
        .onChange(of: model.form) { model.formChanged() }
        .sheet(isPresented: $isPickingZone) {
            TimeZonePickerSheet(selection: $model.form.event.timezone)
        }
        #if os(iOS)
        .sheet(isPresented: $isAddingToCalendar) {
            EventEditView(settings: model.savedForm.event) {
                isAddingToCalendar = false
            }
            .ignoresSafeArea()
        }
        #endif
    }

    /// The type's own hero button, beside Copy Link / Open / Card.
    @ViewBuilder
    private func heroAction(for resource: ManagedResource) -> some View {
        #if os(iOS)
        Button {
            isAddingToCalendar = true
        } label: {
            Label("Add to Calendar", systemImage: "calendar.badge.plus")
        }
        #else
        ShareLink(item: RemoteCalendarFile(client: list.client, slug: resource.slug, name: resource.event.name),
                  preview: SharePreview(resource.event.name.isEmpty ? String(localized: "Event") : resource.event.name)) {
            Label("Share .ics", systemImage: "calendar.badge.plus")
        }
        .disabled(!resource.isEnabled)
        .help(resource.isEnabled
              ? String(localized: "Shares the calendar file visitors download.")
              : String(localized: "Turn the event on to share its calendar file."))
        #endif
    }

    private func whenSection(_ event: Binding<EventSettings>) -> some View {
        let zone = TimeZone(identifier: event.wrappedValue.timezone) ?? .current
        return Section {
            DatePicker(selection: wallClock(event, \.start)) {
                Text("Start Date/Time")
            }
            EditorFieldFootnote(help: nil, error: model.errors[.start])
            DatePicker(selection: wallClock(event, \.end), in: (event.wrappedValue.startDate ?? .distantPast)...) {
                Text("End Date/Time")
            }
            EditorFieldFootnote(help: nil, error: model.errors[.end])
            Button {
                isPickingZone = true
            } label: {
                LabeledContent {
                    HStack(spacing: StudioSpace.s1) {
                        Text(verbatim: TimeZonePickerSheet.title(for: event.wrappedValue.timezone))
                            .studioText(.uiSm)
                            .foregroundStyle(event.wrappedValue.timezone.isEmpty ? Color.studioText3 : Color.studioText2)
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
        } header: {
            EditorSectionHeader(String(localized: "When"))
        } footer: {
            Text("Times are the event’s local time. The calendar file carries the time zone, so every visitor’s calendar shows the right moment.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .environment(\.timeZone, zone)
        .studioRowBackground()
    }

    /// A date picker binding over a wall-clock string, read and written in
    /// the event's zone. Moving the start past the end pulls the end along.
    private func wallClock(_ event: Binding<EventSettings>, _ key: WritableKeyPath<EventSettings, String>) -> Binding<Date> {
        Binding(
            get: {
                let value = event.wrappedValue
                return EventWallClock.date(from: value[keyPath: key], timezone: value.timezone) ?? .now
            },
            set: { date in
                let zone = event.wrappedValue.timezone
                event.wrappedValue[keyPath: key] = EventWallClock.string(from: date, timezone: zone)
                if key == \EventSettings.start, let end = event.wrappedValue.endDate, end < date {
                    event.wrappedValue.end = EventWallClock.string(from: date, timezone: zone)
                }
            }
        )
    }
}

// MARK: - Preview card

/// The event as a ticket, live as you type: a date block (month, day,
/// weekday) torn off by a perforation, then the name, the time range with
/// the event's time zone, and the place. Opaque Studio surfaces; before a
/// name is typed it shows the ticket's shape in muted ink.
struct EventPreviewCard: View {
    let event: EventSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var stubWidth: CGFloat = StudioSpace.s16 + StudioSpace.s4

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 0))

        layout {
            dateStub
            Perforation(isVertical: !dynamicTypeSize.isAccessibilitySize)
            details
        }
        // Stub, perforation and body share one height.
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.studioSurface, in: RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous)
                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
        }
        .animation(reduceMotion ? nil : StudioAnimation.base, value: event)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Event page preview"))
    }

    // MARK: Parts

    @ViewBuilder
    private var dateStub: some View {
        VStack(spacing: StudioSpace.s1) {
            if let start = event.startDate {
                Text(start.formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated)))
                    .studioText(.label)
                Text(start.formatted(Date.FormatStyle(timeZone: zone).day()))
                    .studioText(.display)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(start.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
                    .studioText(.label)
            } else {
                Image(systemName: "calendar")
                    .imageScale(.large)
            }
        }
        .foregroundStyle(hasName ? Color.studioAccentInk : Color.studioText3)
        .frame(minWidth: stubWidth)
        .frame(maxHeight: .infinity)
        .padding(StudioSpace.s4)
        .background(hasName ? Color.studioAccent : Color.studioSurface2)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: StudioRadius.xl,
            bottomLeadingRadius: dynamicTypeSize.isAccessibilitySize ? 0 : StudioRadius.xl,
            bottomTrailingRadius: 0,
            topTrailingRadius: dynamicTypeSize.isAccessibilitySize ? StudioRadius.xl : 0,
            style: .continuous
        ))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Text(verbatim: hasName ? event.name : String(localized: "Your event"))
                .studioText(.title)
                .foregroundStyle(hasName ? Color.studioText : Color.studioText3)
                .fixedSize(horizontal: false, vertical: true)
            if let when = dateLine {
                line(when, systemImage: "calendar")
            }
            if let time = timeLine {
                line(time, systemImage: "clock")
            }
            if !event.location.trimmingCharacters(in: .whitespaces).isEmpty {
                line(event.location, systemImage: "mappin.and.ellipse")
            }
            if !event.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: event.note)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioSpace.s5)
    }

    private func line(_ text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.studioAccentLine)
        }
        .studioText(.ui)
        .foregroundStyle(Color.studioText2)
    }

    // MARK: Text

    private var hasName: Bool { !event.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var zone: TimeZone { TimeZone(identifier: event.timezone) ?? .current }

    /// "Wed 20 Nov 2030", or "20 – 22 Nov 2030" across days.
    private var dateLine: String? {
        guard let start = event.startDate else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = zone
        if let end = event.endDate, end > start, !calendar.isDate(start, inSameDayAs: end) {
            return (start..<end).formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, timeZone: zone))
        }
        return start.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "18:00 – 21:00 GMT": the range in the event's own zone, named.
    private var timeLine: String? {
        guard let start = event.startDate else { return nil }
        let time = Date.FormatStyle(timeZone: zone).hour().minute()
        let zoneName = zone.abbreviation(for: start) ?? zone.identifier
        guard let end = event.endDate, end > start else {
            return "\(start.formatted(time)) \(zoneName)"
        }
        return "\(start.formatted(time)) – \(end.formatted(time)) \(zoneName)"
    }
}

/// The tear line between the ticket's stub and its body.
private struct Perforation: View {
    let isVertical: Bool

    var body: some View {
        Group {
            if isVertical {
                Line(isVertical: true)
                    .stroke(Color.studioBorderStrong, style: StrokeStyle(lineWidth: 1, dash: [StudioSpace.s1, StudioSpace.s1]))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, StudioSpace.s3)
            } else {
                Line(isVertical: false)
                    .stroke(Color.studioBorderStrong, style: StrokeStyle(lineWidth: 1, dash: [StudioSpace.s1, StudioSpace.s1]))
                    .frame(height: 1)
                    .padding(.horizontal, StudioSpace.s3)
            }
        }
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        let isVertical: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            if isVertical {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
            return path
        }
    }
}

#Preview("Edit event") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.event, items: [.link(.previewEvent)], client: app.client)
    NavigationStack {
        EventEditorView(item: .link(.previewEvent), list: list)
    }
    .environment(app)
}

#Preview("New event") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.event, items: [], client: app.client)
    NavigationStack {
        EventEditorView(item: nil, list: list)
    }
    .environment(app)
}
