import SwiftUI
import StudioKit
import CardsiteKit

// The shell's toolbar pieces, shared by Home, Library and (through the
// integrator) Links: the `+` create menu, the account avatar and the inbox
// bell. Each one is a plain view that reads the environment, so a screen
// only places it; the toolbar's glass comes from the system.

// MARK: - Create

/// The `+` menu: every `CreateAction`, in three sections (publish · cards
/// and payments · hosting), each opening its composer sheet.
///
/// Pass `primary` to make a tap run that action at once and a long press
/// open the menu (Links: a tap makes a short link).
struct CreateMenu: View {
    @Environment(AppModel.self) private var app
    var primary: CreateAction? = nil
    /// Links keeps `links.create`, which the UI tests tap.
    var identifier = "shell.create"

    var body: some View {
        Group {
            if let primary {
                Menu {
                    items
                } label: {
                    label
                } primaryAction: {
                    app.composer = primary.composer
                }
            } else {
                Menu {
                    items
                } label: {
                    label
                }
            }
        }
        .accessibilityIdentifier(identifier)
        .help("Create something new")
    }

    private var label: some View {
        Label("New", systemImage: "plus")
    }

    @ViewBuilder
    private var items: some View {
        ForEach(CreateAction.menuGroups, id: \.self) { group in
            Section {
                ForEach(group) { action in
                    Button {
                        app.composer = action.composer
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        }
    }
}

// MARK: - Account

/// The signed-in person as a circular avatar: their initial on the accent
/// tile. Opens the account sheet. Identity imagery, so it never takes glass
/// of its own; on OS 26 its toolbar item drops the shared glass background
/// (``AccountToolbarItem``).
struct AccountAvatarButton: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellRouter.self) private var router
    @Environment(InboxModel.self) private var inbox: InboxModel?
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = StudioSpace.s8

    var body: some View {
        Button {
            router.isAccountPresented = true
        } label: {
            Text(app.user?.initial ?? "?")
                .studioText(.ui)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioAccentInk)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.studioAccent))
                .contentShape(Circle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.94))
        .accessibilityLabel(Text("Account"))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text("Profile, workspace, inbox, preferences and sign out"))
        .accessibilityIdentifier(AppDestination.account.navIdentifier)
        .help("Account")
    }

    private var accessibilityValue: String {
        let name = app.user?.name ?? ""
        let unread = inbox?.unreadCount ?? 0
        guard unread > 0 else { return name }
        return String(localized: "\(name), \(unread) unread in Inbox")
    }
}

/// The avatar as the trailing toolbar item, in a group of its own: on
/// iOS 26 the shared glass background is hidden, as Books splits its
/// avatar out, so the accent disc stands alone.
struct AccountToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                AccountAvatarButton()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                AccountAvatarButton()
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            AccountAvatarButton()
        }
        #endif
    }
}

// MARK: - Inbox

/// The bell on Home: pushes the Inbox onto Home's stack. The symbol carries
/// the badge (`bell.badge`, as Mail does) and VoiceOver reads the count.
struct InboxBellLink: View {
    @Environment(InboxModel.self) private var inbox

    var body: some View {
        NavigationLink(value: AppDestination.inbox) {
            Label {
                Text("Inbox")
            } icon: {
                Image(systemName: inbox.unreadCount > 0 ? "bell.badge" : "bell")
                    .symbolRenderingMode(inbox.unreadCount > 0 ? SymbolRenderingMode.multicolor : SymbolRenderingMode.monochrome)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityValue(inbox.unreadCount > 0 ? Text("\(inbox.unreadCount) unread") : Text(""))
        .accessibilityIdentifier("home.inbox")
        .help("Inbox")
    }
}

// MARK: - Subtitle

extension View {
    /// The workspace (or any short context) under the navigation title:
    /// `navigationSubtitle` on iOS 26 and on macOS; nothing before iOS 26
    /// or on visionOS.
    @ViewBuilder
    func shellSubtitle(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            #if os(macOS)
            navigationSubtitle(text)
            #elseif os(iOS)
            if #available(iOS 26.0, *) {
                navigationSubtitle(text)
            } else {
                self
            }
            #else
            self
            #endif
        } else {
            self
        }
    }
}
