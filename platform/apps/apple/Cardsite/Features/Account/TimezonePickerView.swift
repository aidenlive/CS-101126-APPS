import SwiftUI
import StudioKit
import CardsiteKit

/// The full IANA list, searchable, as the web's TimezonePicker offers it.
/// Choosing a zone saves it straight away with `PUT /account`.
struct TimezonePickerView: View {
    let model: AccountSettingsModel
    let current: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var saving: String? = nil
    @State private var error: String? = nil

    private static let zones: [Zone] = TimeZone.knownTimeZoneIdentifiers.sorted().map(Zone.init)

    struct Zone: Identifiable, Hashable {
        let id: String
        /// "America/New York" — underscores read badly aloud and on screen.
        var title: String { id.replacingOccurrences(of: "_", with: " ") }
        /// "GMT+2" or "GMT+5:30" for the zone's offset right now.
        var offset: String {
            guard let zone = TimeZone(identifier: id) else { return "" }
            let seconds = zone.secondsFromGMT()
            guard seconds != 0 else { return "GMT" }
            let sign = seconds < 0 ? "-" : "+"
            let hours = abs(seconds) / 3600
            let minutes = (abs(seconds) % 3600) / 60
            return minutes == 0 ? "GMT\(sign)\(hours)" : "GMT\(sign)\(hours):\(String(format: "%02d", minutes))"
        }
    }

    private var visible: [Zone] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.zones }
        return Self.zones.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.offset.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowSeparator(.hidden)
                }
                ForEach(visible) { zone in
                    Button {
                        Task { await choose(zone) }
                    } label: {
                        HStack(spacing: StudioSpace.s3) {
                            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                                Text(verbatim: zone.title)
                                    .studioText(.ui)
                                    .foregroundStyle(Color.studioText)
                                Text(verbatim: zone.offset)
                                    .studioText(.uiSm)
                                    .studioMuted()
                            }
                            Spacer(minLength: StudioSpace.s2)
                            if saving == zone.id {
                                ProgressView()
                            } else if zone.id == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.studioAccentLine)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(zone.id == current ? .isSelected : [])
                    .disabled(saving != nil)
                }
            }
            .searchable(text: $query, prompt: Text("Search timezones"))
            .navigationTitle("Timezone")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Couldn’t save the timezone",
                   isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .cardsiteSheet(.form)
    }

    private func choose(_ zone: Zone) async {
        guard zone.id != current else { dismiss(); return }
        saving = zone.id
        defer { saving = nil }
        do {
            let user = try await model.saveTimezone(zone.id)
            // Only a complete profile replaces the signed-in one.
            if user.id != 0, !user.email.isEmpty { app.replaceUser(user) }
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}
