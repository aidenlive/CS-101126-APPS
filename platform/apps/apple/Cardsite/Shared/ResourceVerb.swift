import SwiftUI
import StudioKit

/*
 One vocabulary for what you can do to a resource, and one builder for the
 menus and swipe actions that offer it, so a context menu, a swipe, a
 header button and a toolbar never name the same action differently.

     let actions = ResourceActionSet(url: url, cardURL: card, isEnabled: link.isEnabled,
                                     statistics: { statisticsFor = link },
                                     duplicate: { Task { await duplicate(link) } },
                                     setEnabled: { on in Task { await setEnabled(link, on) } },
                                     delete: { pendingDelete = link })
     row
         .contextMenu { ResourceMenuItems(actions: actions) }
         .resourceSwipeActions(actions)

 Control labels are title case (HIG); the state words are "Live" and "Off"
 everywhere: pills, the switch and VoiceOver.
 */

/// The verbs, as control labels.
enum ResourceVerb: CaseIterable {
    case copyLink
    case openInBrowser
    case showCard
    case share
    case statistics
    case duplicate
    case turnOn
    case turnOff
    case edit
    case delete

    var title: String {
        switch self {
        case .copyLink: return String(localized: "Copy Link")
        case .openInBrowser: return String(localized: "Open in Browser")
        case .showCard: return String(localized: "Show Card")
        case .share: return String(localized: "Share…")
        case .statistics: return String(localized: "Statistics")
        case .duplicate: return String(localized: "Duplicate")
        case .turnOn: return String(localized: "Turn On")
        case .turnOff: return String(localized: "Turn Off")
        case .edit: return String(localized: "Edit…")
        case .delete: return String(localized: "Delete…")
        }
    }

    var systemImage: String {
        switch self {
        case .copyLink: return "doc.on.doc"
        case .openInBrowser: return "safari"
        case .showCard: return "rectangle.portrait.on.rectangle.portrait"
        case .share: return "square.and.arrow.up"
        case .statistics: return "chart.bar.xaxis"
        case .duplicate: return "plus.square.on.square"
        case .turnOn: return "play.circle"
        case .turnOff: return "pause.circle"
        case .edit: return "pencil"
        case .delete: return "trash"
        }
    }

    /// The verb as a `Label`, for menus, swipes and form rows.
    var label: some View {
        Label(title, systemImage: systemImage)
    }

    /// Turn Off for a live resource, Turn On for one that is off.
    static func toggle(isEnabled: Bool) -> ResourceVerb {
        isEnabled ? .turnOff : .turnOn
    }
}

/// A resource's state, as pills, the switch and VoiceOver say it.
enum ResourceState: Equatable {
    case live
    case off
    /// Live, but its address is in the release window.
    case lapsing

    init(isEnabled: Bool, isLapsing: Bool) {
        if !isEnabled {
            self = .off
        } else if isLapsing {
            self = .lapsing
        } else {
            self = .live
        }
    }

    var title: String {
        switch self {
        case .live: return String(localized: "Live")
        case .off: return String(localized: "Off")
        case .lapsing: return String(localized: "Lapsing")
        }
    }

    var tone: StudioTone {
        switch self {
        case .live: return .success
        case .off: return .neutral
        case .lapsing: return .warning
        }
    }

    var pill: StudioStatusPill {
        StudioStatusPill(title, tone: tone)
    }
}

/// What can be done to one resource. A nil action, or a nil URL, leaves
/// its item out of the menu, the swipes and the header.
struct ResourceActionSet {
    var url: URL? = nil
    var cardURL: URL? = nil
    /// Nil when the resource has no on/off state.
    var isEnabled: Bool? = nil
    var edit: (() -> Void)? = nil
    var statistics: (() -> Void)? = nil
    var duplicate: (() -> Void)? = nil
    var setEnabled: ((Bool) -> Void)? = nil
    var delete: (() -> Void)? = nil

    /// Copies the address, with a haptic and a toast when the shell has one.
    @MainActor
    static func copy(_ url: URL, toasts: StudioToastCenter?) {
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
        toasts?.show(String(localized: "Link copied"), variant: .success)
    }
}

/// The context menu (or `Menu`) for a resource, in the standard order:
/// edit; copy, open, share, card; statistics, duplicate, on/off; delete.
struct ResourceMenuItems: View {
    let actions: ResourceActionSet
    @Environment(\.openURL) private var openURL
    @Environment(\.toasts) private var toasts

    var body: some View {
        if let edit = actions.edit {
            Button(action: edit) { ResourceVerb.edit.label }
        }
        if let url = actions.url {
            Button { ResourceActionSet.copy(url, toasts: toasts) } label: { ResourceVerb.copyLink.label }
            Button { openURL(url) } label: { ResourceVerb.openInBrowser.label }
            ShareLink(item: url) { ResourceVerb.share.label }
        }
        if let card = actions.cardURL {
            Button { openURL(card) } label: { ResourceVerb.showCard.label }
        }
        if hasOpenGroup, hasManageGroup {
            Divider()
        }
        if let statistics = actions.statistics {
            Button(action: statistics) { ResourceVerb.statistics.label }
        }
        if let duplicate = actions.duplicate {
            Button(action: duplicate) { ResourceVerb.duplicate.label }
        }
        if let setEnabled = actions.setEnabled, let isEnabled = actions.isEnabled {
            Button { setEnabled(!isEnabled) } label: { ResourceVerb.toggle(isEnabled: isEnabled).label }
        }
        if let delete = actions.delete {
            if hasOpenGroup || hasManageGroup {
                Divider()
            }
            Button(role: .destructive, action: delete) { ResourceVerb.delete.label }
        }
    }

    private var hasOpenGroup: Bool {
        actions.edit != nil || actions.url != nil || actions.cardURL != nil
    }

    private var hasManageGroup: Bool {
        actions.statistics != nil || actions.duplicate != nil
            || (actions.setEnabled != nil && actions.isEnabled != nil)
    }
}

extension View {
    /// The same actions as ``ResourceMenuItems``, as swipes: Copy Link and
    /// Open in Browser leading; Delete, Duplicate and Statistics trailing.
    func resourceSwipeActions(_ actions: ResourceActionSet) -> some View {
        modifier(ResourceSwipeActions(actions: actions))
    }
}

private struct ResourceSwipeActions: ViewModifier {
    let actions: ResourceActionSet
    @Environment(\.openURL) private var openURL
    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let delete = actions.delete {
                    Button(role: .destructive, action: delete) { ResourceVerb.delete.label }
                }
                if let duplicate = actions.duplicate {
                    Button(action: duplicate) { ResourceVerb.duplicate.label }
                        .tint(.studioInfo)
                }
                if let statistics = actions.statistics {
                    Button(action: statistics) { ResourceVerb.statistics.label }
                        .tint(.studioAccentLine)
                } else if let edit = actions.edit {
                    Button(action: edit) { ResourceVerb.edit.label }
                        .tint(.studioAccentLine)
                }
            }
            .swipeActions(edge: .leading) {
                if let url = actions.url {
                    Button { ResourceActionSet.copy(url, toasts: toasts) } label: { ResourceVerb.copyLink.label }
                        .tint(.studioInfo)
                    Button { openURL(url) } label: { ResourceVerb.openInBrowser.label }
                        .tint(.studioText2)
                }
            }
    }
}
