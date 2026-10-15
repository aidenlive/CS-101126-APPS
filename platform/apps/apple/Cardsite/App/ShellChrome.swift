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
/// open the menu (Links: a tap makes a short link). `performPrimary`
/// replaces the shell's composer for that tap, for a screen that presents
/// the editor itself (Links selects the link it creates).
struct CreateMenu: View {
    @Environment(AppModel.self) private var app
    var primary: CreateAction? = nil
    /// Links keeps `links.create`, which the UI tests tap.
    var identifier = "shell.create"
    var performPrimary: (() -> Void)? = nil

    var body: some View {
        Group {
            #if os(macOS)
            if let primary {
                // A Mac toolbar draws a primary-action menu as a split
                // pull-down whose centre click is ambiguous, so the Mac
                // gets a plain + button beside the full menu.
                Button {
                    runPrimary(primary)
                } label: {
                    label
                }
                .accessibilityIdentifier(identifier)
                .help(primary.title)
                Menu {
                    items
                } label: {
                    Label("More New Items", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("\(identifier).menu")
                .help("Create something new")
            } else {
                Menu {
                    items
                } label: {
                    label
                }
                .accessibilityIdentifier(identifier)
                .help("Create something new")
            }
            #else
            if let primary {
                Menu {
                    items
                } label: {
                    label
                } primaryAction: {
                    runPrimary(primary)
                }
                .accessibilityIdentifier(identifier)
                .help("Create something new")
            } else {
                Menu {
                    items
                } label: {
                    label
                }
                .accessibilityIdentifier(identifier)
                .help("Create something new")
            }
            #endif
        }
    }

    private func runPrimary(_ primary: CreateAction) {
        if let performPrimary {
            performPrimary()
        } else {
            app.composer = primary.composer
        }
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

/// The signed-in person's identity portrait (`StudioAvatar`, from the
/// identity tokens, never the accent: the accent belongs to the `+`
/// action beside it). Opens the account sheet.
///
/// A plain toolbar button around the 36pt portrait rather than
/// `StudioAccountButton`: that control draws its own 52pt glass pill for
/// Studio's floating chrome, and here the bar is the system's, which
/// already sizes and backs its items. On OS 26 the item drops the shared
/// glass background (``SwiftUI/View/accountToolbarItem()``) so the
/// portrait stands alone, as Books splits its avatar out.
struct AccountAvatarButton: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellRouter.self) private var router
    @Environment(InboxModel.self) private var inbox: InboxModel?

    var body: some View {
        Button {
            router.isAccountPresented = true
        } label: {
            StudioAvatar(initial: app.user?.initial ?? "?", name: app.user?.name, size: .md)
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

extension View {
    /// The avatar as the trailing toolbar item, in a group of its own: on
    /// iOS 26 the shared glass background is hidden, as Books splits its
    /// avatar out, so the identity portrait stands alone. Not on the Mac, where
    /// the account lives in the sidebar.
    ///
    /// A view modifier rather than `ToolbarContent`: the iOS 26 branch needs
    /// `if #available` around a toolbar-content modifier, which only
    /// `ViewBuilder` erases (`buildLimitedAvailability`) on every SDK the
    /// app builds with.
    @ViewBuilder
    func accountToolbarItem() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountAvatarButton()
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountAvatarButton()
                }
            }
        }
        #elseif os(visionOS)
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                AccountAvatarButton()
            }
        }
        #else
        self
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
