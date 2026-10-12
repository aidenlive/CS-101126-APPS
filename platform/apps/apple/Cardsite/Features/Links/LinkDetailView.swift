import SwiftUI
import Charts
import StudioKit
import CardsiteKit

struct LinkDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(LinksModel.self) private var model
    let link: Resource

    @State private var traffic: LinkTrafficModel?
    @State private var isEditingDestination = false
    @State private var isTogglingEnabled = false
    @State private var actionError: String?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpace.s6) {
                addressCard
                destinationCard
                if let traffic {
                    TrafficSection(model: traffic)
                }
                FormErrorText(message: actionError)
            }
            .padding(StudioSpace.s6)
            .readableWidth(760)
        }
        .background(Color.studioBg)
        .navigationTitle(link.slug)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let url = app.addresses.url(for: link.slug) {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingDestination) {
            DestinationEditor(link: link)
        }
        .task {
            if traffic == nil {
                let traffic = LinkTrafficModel(client: model.client, linkID: link.id)
                traffic.onError = app.handle
                self.traffic = traffic
            }
        }
    }

    // MARK: Address

    private var addressCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                HStack {
                    StudioKicker(String(localized: "Address"))
                    Spacer()
                    if !link.isEnabled {
                        StudioStatusPill(String(localized: "Off"), tone: .neutral)
                    } else if link.isLapsing {
                        StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
                    } else {
                        StudioStatusPill(String(localized: "Live"), tone: .success)
                    }
                }
                Text(verbatim: app.addresses.display(for: link.slug))
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { addressActions }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { addressActions }
                }

                if link.isLapsing {
                    StudioBanner(
                        lead: String(localized: "This address is in its release window."),
                        message: String(localized: "It may be released to others soon. How addresses are kept: cardsite.com/url-lifecycle."),
                        tone: .warning
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var addressActions: some View {
        StudioButton(copied ? String(localized: "Copied") : String(localized: "Copy"),
                     systemImage: copied ? "checkmark" : "doc.on.doc",
                     variant: .primary) {
            copy()
        }
        if let url = app.addresses.url(for: link.slug) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            Link(destination: url) {
                Label("Open", systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
        if let card = app.addresses.cardURL(for: link.slug) {
            Link(destination: card) {
                Label("View Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens the summary card at \(app.addresses.display(for: "@" + link.slug))")
        }
    }

    private func copy() {
        guard let url = app.addresses.url(for: link.slug) else { return }
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    // MARK: Destination

    private var destinationCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                StudioKicker(String(localized: "Destination"))
                if let destination = link.destination, let url = URL(string: destination) {
                    Link(destination: url) {
                        Text(verbatim: destination)
                            .studioText(.body)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    .textSelection(.enabled)
                } else {
                    Text("No destination").studioText(.body).studioMuted()
                }
                HStack(spacing: StudioSpace.s2) {
                    StudioButton(String(localized: "Change Destination"), systemImage: "pencil", variant: .outline) {
                        isEditingDestination = true
                    }
                    Spacer()
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { link.isEnabled },
                    set: { newValue in Task { await setEnabled(newValue) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Address is live").studioText(.ui)
                        Text("When off, visitors see a not-found page. The address stays yours.")
                            .studioText(.uiSm)
                            .studioMuted()
                    }
                }
                .toggleStyle(.switch)
                .disabled(isTogglingEnabled)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) async {
        isTogglingEnabled = true
        defer { isTogglingEnabled = false }
        actionError = nil
        do {
            _ = try await model.update(link, isEnabled: enabled)
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
    }
}

// MARK: - Traffic

private struct TrafficSection: View {
    @Bindable var model: LinkTrafficModel

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                StudioSectionHeader(String(localized: "Traffic"))
                Spacer()
                Picker("Period", selection: $model.window) {
                    ForEach(LinkTrafficModel.Window.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            // Reloads on appear and whenever the period changes; SwiftUI
            // cancels the previous load, so a fast switch can't land late.
            .task(id: model.window) { await model.load() }

            switch model.state {
            case .idle, .loading:
                StudioCard {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            case .failed(let error):
                StudioCard {
                    VStack(spacing: StudioSpace.s3) {
                        Text(error.localizedDescription).studioText(.uiSm).studioMuted()
                            .multilineTextAlignment(.center)
                        StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline) {
                            Task { await model.load() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            case .loaded(let snapshot):
                content(snapshot)
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: LinkTrafficModel.Snapshot) -> some View {
        HStack(spacing: StudioSpace.s3) {
            StatTile(title: String(localized: "Views"), value: snapshot.totalViews)
            StatTile(title: String(localized: "Visitors a day"), value: snapshot.averageDailyVisitors)
        }
        StudioCard {
            if snapshot.days.isEmpty {
                Text("No visits in this period yet. Share the address and they'll show up here.")
                    .studioText(.uiSm)
                    .studioMuted()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(snapshot.days) { day in
                    if let date = day.day {
                        BarMark(
                            x: .value("Day", date, unit: .day),
                            y: .value("Views", day.pageviews)
                        )
                        .foregroundStyle(Color.studioAccentLine)
                        .cornerRadius(3)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 200)
            }
        }
        if !snapshot.referrers.isEmpty || !snapshot.countries.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: StudioSpace.s3) {
                    BreakdownList(title: String(localized: "Top referrers"), rows: snapshot.referrers)
                    BreakdownList(title: String(localized: "Top countries"), rows: snapshot.countries, isCountry: true)
                }
                VStack(spacing: StudioSpace.s3) {
                    BreakdownList(title: String(localized: "Top referrers"), rows: snapshot.referrers)
                    BreakdownList(title: String(localized: "Top countries"), rows: snapshot.countries, isCountry: true)
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: Int

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(title).studioText(.label).studioMuted()
                Text(value.grouped)
                    .studioText(.title)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BreakdownList: View {
    let title: String
    let rows: [TrafficBreakdown]
    var isCountry = false

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(title).studioText(.label).studioMuted()
                if rows.isEmpty {
                    Text("Nothing yet").studioText(.uiSm).studioMuted()
                }
                ForEach(rows.prefix(5)) { row in
                    HStack {
                        Text(verbatim: displayName(row.label))
                            .studioText(.uiSm)
                            .lineLimit(1)
                        Spacer()
                        Text(row.pageviews.grouped)
                            .studioText(.uiSm)
                            .monospacedDigit()
                            .foregroundStyle(Color.studioText2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayName(_ label: String) -> String {
        if label.isEmpty { return String(localized: "Direct") }
        if isCountry, label.count == 2 {
            return Locale.current.localizedString(forRegionCode: label) ?? label
        }
        return label
    }
}

// MARK: - Destination editor

private struct DestinationEditor: View {
    @Environment(LinksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: Resource

    @State private var destination: String
    @State private var error: String?
    @State private var isSaving = false

    init(link: Resource) {
        self.link = link
        _destination = State(initialValue: link.destination ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                StudioTextField(String(localized: "New destination"), text: $destination,
                                placeholder: "example.com/menu",
                                help: String(localized: "The address and any printed QR codes keep working and send people here instead."),
                                errorMessage: error)
                    .plainEntry()
                    #if os(iOS)
                    .textContentType(.URL)
                    #endif
                    .onSubmit { Task { await save() } }
                Spacer()
            }
            .padding(StudioSpace.s6)
            .background(Color.studioBg)
            .navigationTitle("Change Destination")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 240)
        #endif
    }

    private func save() async {
        guard let url = Destination.normalized(destination) else {
            error = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await model.update(link, destination: url)
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}
