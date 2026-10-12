import SwiftUI

/*
 The dock — compact bottom chrome, as one control.

 WHAT THIS REPLACES

 Until v1.9 the compact layout shipped two unrelated floating objects:
 a glass tab pill and a separate accent-filled compose disc. Both
 floated at the same inset, both were circular, both were 52pt, and
 the account avatar was a THIRD accent disc in the same view. Three
 peers, no hierarchy — nothing told you which one had consequence,
 because two of them were painted identically.

 The dock collapses that into one glass container holding four roles,
 in reading order:

   nav      up to 3 destinations   — navigation
   divider  hairline               — separation
   search   the search affordance  — retrieval
   action   ONE accent disc        — creation

 The action disc is `StudioLayout.dockAction` (44pt), deliberately
 smaller than a pill, so it reads as a CHILD of the dock rather than a
 competing object floating beside it.

 WHERE THIS IS AND IS NOT USED

 On iOS 26 the system's Liquid Glass tab bar already does all of this,
 including the search role and the minimize-on-scroll behaviour, and
 matching it by hand is a losing race against the material. So the
 native path stays native — see `StudioAppShell.nativeTabs` — and this
 view is the fallback for iOS 17–25 and macOS, plus the reference
 implementation the web dock is generated against.

 STATE

 `State.rest`   full dock
 `State.min`    minimised: nav collapses, dock contracts around
                search + action. The hand-rolled equivalent of
                `.tabBarMinimizeBehavior(.onScrollDown)`.
 `State.search` search morph: nav collapses, the field spans the dock,
                the action scales out, Cancel takes its place.

 The container is the same view in every state, so the glass stretches
 rather than one panel swapping for another. That continuity is the
 whole reason to use a material.
 */

/// How many destinations the compact dock shows. Three-plus-compose is the
/// ceiling the iOS 26 tab bar is designed around; the rest belong in a
/// sidebar or an overflow menu.
let studioCompactTabLimit = 3

/// One dock destination.
public struct StudioDockItem<Tag: Hashable>: Identifiable {
    public let tag: Tag
    public let title: String
    public let systemImage: String
    public let selectedSystemImage: String

    public var id: Tag { tag }

    public init(
        tag: Tag,
        title: String,
        systemImage: String,
        selectedSystemImage: String? = nil
    ) {
        self.tag = tag
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage ?? "\(systemImage).fill"
    }
}

public struct StudioDock<Tag: Hashable>: View {
    public enum State: Equatable {
        case rest, min, search
    }

    private let items: [StudioDockItem<Tag>]
    private let state: State
    private let searchTitle: String
    private let onSearch: (() -> Void)?
    private let onCancel: (() -> Void)?
    private let actionTitle: String
    private let actionSystemImage: String
    private let onAction: (() -> Void)?

    @Binding private var selection: Tag
    @Environment(\.studioHaptics) private var haptics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        selection: Binding<Tag>,
        items: [StudioDockItem<Tag>],
        state: State = .rest,
        searchTitle: String = "Search",
        onSearch: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        actionTitle: String = "Compose",
        actionSystemImage: String = "plus",
        onAction: (() -> Void)? = nil
    ) {
        self._selection = selection
        /* studioCompactTabLimit, not a second constant of the same
           value — the native path already caps at it, and two limits
           that mean the same thing are two limits that can drift. */
        self.items = Array(items.prefix(studioCompactTabLimit))
        self.state = state
        self.searchTitle = searchTitle
        self.onSearch = onSearch
        self.onCancel = onCancel
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.onAction = onAction
    }

    private var navCollapsed: Bool { state != .rest }

    public var body: some View {
        HStack(spacing: 4) {
            if !navCollapsed {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        navButton(item)
                    }
                }
                .transition(
                    reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                )

                if onSearch != nil {
                    Rectangle()
                        .fill(Color.studioBorder)
                        .frame(width: 0.5, height: 22)
                        .padding(.horizontal, 3)
                }
            }

            if onSearch != nil {
                searchButton
            }

            if let onAction {
                /* Stays in the hierarchy during the morph and scales
                   out, matching the web dock exactly: the container is
                   one object that stretches, so removing a child
                   mid-transition makes it pop instead of animate.
                   Inert rather than absent — hidden from accessibility
                   and non-interactive, never merely invisible. */
                Button {
                    haptics.play(.selection)
                    onAction()
                } label: {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.studioAccentInk)
                        .frame(width: StudioLayout.dockAction, height: StudioLayout.dockAction)
                        .background(Color.studioAccent, in: Circle())
                }
                .buttonStyle(StudioPressStyle(scale: 0.9))
                .accessibilityLabel(actionTitle)
                .scaleEffect(state == .search && !reduceMotion ? 0.4 : 1)
                .opacity(state == .search ? 0 : 1)
                .frame(width: state == .search ? 0 : StudioLayout.dockAction)
                .disabled(state == .search)
                .accessibilityHidden(state == .search)
            }

            if state == .search, let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.custom(StudioFontFamily.body, size: 15))
                    .foregroundStyle(Color.studioText2)
                    .padding(.horizontal, StudioSpace.s3)
                    .frame(height: StudioLayout.tapTarget)
                    .transition(.opacity)
            }
        }
        .padding(4)
        .studioGlass()
        .animation(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: reduceMotion), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary")
    }

    private func navButton(_ item: StudioDockItem<Tag>) -> some View {
        let isCurrent = item.tag == selection
        return Button {
            haptics.play(.selection)
            withAnimation(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: reduceMotion)) {
                selection = item.tag
            }
        } label: {
            Image(systemName: isCurrent ? item.selectedSystemImage : item.systemImage)
                .font(.system(size: 20, weight: isCurrent ? .semibold : .regular))
                /* Ink, not fill. Spending the accent here too is what
                   flattened the hierarchy: the current tab and the
                   compose action became the same object visually. The
                   accent survives only as the indicator bar below. */
                .foregroundStyle(isCurrent ? Color.studioText : Color.studioText3)
                .frame(width: StudioLayout.tapTarget, height: StudioLayout.tapTarget)
                .background {
                    if isCurrent {
                        Circle().fill(Color.studioSurface2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isCurrent {
                        Capsule()
                            .fill(Color.studioAccentLine)
                            .frame(width: 14, height: 2.5)
                            .padding(.bottom, 5)
                    }
                }
        }
        .buttonStyle(StudioPressStyle(scale: 0.92))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }

    private var searchButton: some View {
        Button {
            onSearch?()
        } label: {
            HStack(spacing: StudioSpace.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: StudioLayout.tapTarget)
                if state == .search {
                    Text(searchTitle)
                        .font(.custom(StudioFontFamily.body, size: 15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(state == .search ? Color.studioText : Color.studioText3)
            .frame(height: StudioLayout.tapTarget)
            .frame(maxWidth: state == .search ? .infinity : StudioLayout.tapTarget)
            .background {
                if state == .search {
                    Capsule().fill(Color.studioSurface2)
                }
            }
        }
        .buttonStyle(StudioPressStyle(scale: 0.95))
        .accessibilityLabel(searchTitle)
    }
}
