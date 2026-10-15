import SwiftUI
import StudioKit
import CardsiteKit

/// The account sheet, opened from the avatar on Home and Library: who is
/// signed in, the workspace switcher, then Inbox, Workspace, Preferences
/// and Account & Security, then Sign Out.
///
/// A medium detent first, so it reads as a menu over the page (the system
/// draws it in glass on OS 26); opening a row grows it to large, where the
/// pushed screen gets the room it needs. Each row pushes the destination's
/// own stack-free view from the registry, so nothing here duplicates the
/// Inbox, Workspace, Preferences or Account screens.
struct AccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(InboxModel.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .medium
    @State private var confirmSignOut = false

    /// The rows under the switcher, in order.
    static let rows: [AppDestination] = [.inbox, .workspace, .preferences, .account]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let user = app.user {
                    Section {
                        AccountSheetHeader(user: user)
                    }
                    .studioRowBackground()
                }

                Section {
                    WorkspacePickerRow()
                } footer: {
                    Text("Links, pages and codes belong to a workspace. Switch to see another one’s.")
                }
                .studioRowBackground()

                Section {
                    ForEach(Self.rows) { destination in
                        NavigationLink(value: destination) {
                            Label(Self.title(for: destination), systemImage: Self.systemImage(for: destination))
                        }
                        .badge(destination == .inbox ? inbox.unreadCount : 0)
                        .accessibilityIdentifier(destination.accountSheetIdentifier)
                    }
                }
                .studioRowBackground()

                Section {
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .accessibilityIdentifier("account.sheet.signOut")
                }
                .studioRowBackground()
            }
            // The rows are opaque Studio surfaces; between them the sheet's
            // own material shows (glass at the medium detent on OS 26).
            .scrollContentBackground(.hidden)
            .tint(Color.studioAccentLine)
            .accessibilityIdentifier("account.sheet")
            .navigationTitle("Your Account")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .accessibilityIdentifier("account.sheet.close")
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                DestinationView(destination: destination)
            }
            .confirmationDialog("Sign out of Cardsite?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    Task { [app] in await app.signOut() }
                }
            }
        }
        .task { [inbox] in await inbox.refreshUnreadCount() }
        .onChange(of: path.count) { _, depth in
            if depth > 0 { detent = .large }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: CardsiteMeasure.sheet.width, minHeight: CardsiteMeasure.sheet.width)
        #endif
    }

    /// The sheet's names: the Account screen holds profile and security,
    /// so its row says both.
    static func title(for destination: AppDestination) -> String {
        destination == .account ? String(localized: "Account & Security") : destination.title
    }

    static func systemImage(for destination: AppDestination) -> String {
        destination == .account ? "lock.shield" : destination.systemImage
    }
}

/// The sheet's head: the initial on the accent disc, the name in display
/// type, the email exactly as typed (never an uppercase style).
private struct AccountSheetHeader: View {
    let user: User
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = StudioSpace.s16
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s3))
            : AnyLayout(HStackLayout(spacing: StudioSpace.s4))
        layout {
            Text(user.initial)
                .studioText(.title)
                .foregroundStyle(Color.studioAccentInk)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.studioAccent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(user.name.isEmpty ? String(localized: "Your account") : user.name)
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: user.email)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, StudioSpace.s2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Account sheet") {
    let app = AppModel.preview()
    let inbox = InboxModel(client: app.client)
    return Color.studioBg
        .sheet(isPresented: .constant(true)) {
            AccountSheet()
        }
        .environment(app)
        .environment(inbox)
        .environment(ShellRouter())
}
#endif
