import SwiftUI

/*
 The account layer (from Studio 1.10).

 One account control per window, owned by the app's root chrome — never
 mounted per screen, or two fight for the corner the moment the app
 navigates. Tapping it opens the account sheet: profile, then whatever
 rows the app appends, then sign-out.

     @State private var showsAccount = false
     …
     StudioAccountButton(name: user.name) { showsAccount = true }
     …
     .sheet(isPresented: $showsAccount) {
         StudioAccountSheet(
             config: .init(name: user.name, email: user.email) {
                 StudioAccountRow(systemImage: "gearshape", title: "Settings") { … }
             },
             onSignOut: { appModel.signOut() }
         )
     }
 */

/// Who is signed in, and what the sheet shows for them.
public struct StudioAccountConfig {
    public let name: String
    public let email: String
    /// Defaults to the first letter of `name`.
    public let initial: String
    /// Extra rows appended to the sheet, below the built-in ones.
    public let extraRows: AnyView?

    public init(name: String, email: String, initial: String? = nil) {
        self.name = name
        self.email = email
        self.initial = initial ?? String(name.prefix(1))
        self.extraRows = nil
    }

    public init<Rows: View>(
        name: String,
        email: String,
        initial: String? = nil,
        @ViewBuilder extraRows: () -> Rows
    ) {
        self.name = name
        self.email = email
        self.initial = initial ?? String(name.prefix(1))
        self.extraRows = AnyView(extraRows())
    }
}

/// The account sheet: optional navigation rows (compact-overflow
/// destinations, injected by the shell), profile header, app-provided
/// rows, and sign-out. Presented at a medium detent so it reads as a
/// menu, not a screen takeover.
///
/// Deliberately does NOT paint its own background or corner radius:
/// on iOS 26 the system sheet brings the Liquid Glass treatment and
/// concentric corners itself, and overriding either flattens it back
/// to an iOS-17 slab — which is exactly what the first cut shipped.
public struct StudioAccountSheet<NavRows: View>: View {
    private let config: StudioAccountConfig
    private let onSignOut: (() -> Void)?
    private let navRows: NavRows

    @Environment(\.dismiss) private var dismiss

    public init(
        config: StudioAccountConfig,
        onSignOut: (() -> Void)? = nil,
        @ViewBuilder navRows: () -> NavRows
    ) {
        self.config = config
        self.onSignOut = onSignOut
        self.navRows = navRows()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            // Overflow navigation, when the shell has any to give.
            // Placed directly in the stack: an EmptyView here
            // contributes neither height nor a spacing slot.
            navRows

            // Profile header
            HStack(spacing: StudioSpace.s4) {
                /* The identity primitive, not another hand-rolled
                   accent disc. This header was the third place in the
                   package painting a person in --accent. */
                StudioAvatar(initial: config.initial, name: config.name, size: .lg)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                    // Not `.meta`: that style is uppercase, and an email
                    // address must render exactly as typed.
                    Text(config.email)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 0.5)

            VStack(spacing: 2) {
                if let extraRows = config.extraRows {
                    extraRows
                }
                if let onSignOut {
                    StudioAccountRow(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        isDestructive: true
                    ) {
                        dismiss()
                        onSignOut()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(StudioSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

public extension StudioAccountSheet where NavRows == EmptyView {
    init(config: StudioAccountConfig, onSignOut: (() -> Void)? = nil) {
        self.init(config: config, onSignOut: onSignOut, navRows: { EmptyView() })
    }
}

/// One row of the account sheet. Use it for app-specific entries too.
public struct StudioAccountRow: View {
    private let systemImage: String
    private let title: String
    private let detail: String?
    private let isDestructive: Bool
    private let action: () -> Void

    public init(
        systemImage: String,
        title: String,
        detail: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.isDestructive = isDestructive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s3) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(minWidth: 24)
                Text(title).studioText(.ui)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .studioText(.meta)
                        .foregroundStyle(Color.studioText3)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.studioText4)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isDestructive ? Color.studioError : Color.studioText)
            .padding(.horizontal, StudioSpace.s3)
            .frame(maxWidth: .infinity, minHeight: StudioSpace.s12, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Account button

/// The pressable account control: a 52pt glass pill around a 36pt
/// identity portrait — the same metric as every other piece of floating
/// chrome. Pass `showsCaret: false` where space is tight (compact widths).
public struct StudioAccountButton: View {
    private let initial: String?
    private let name: String?
    private let label: String
    private let showsCaret: Bool
    private let action: () -> Void

    public init(
        initial: String? = nil,
        name: String? = nil,
        label: String = "Account menu",
        showsCaret: Bool = true,
        action: @escaping () -> Void
    ) {
        self.initial = initial
        self.name = name
        self.label = label
        self.showsCaret = showsCaret
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s2) {
                StudioAvatar(initial: initial, name: name)
                if showsCaret {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.studioText3)
                }
            }
            .padding(.horizontal, StudioSpace.s2)
            .frame(minHeight: StudioLayout.pillHeight)
            .studioGlass(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(StudioPressStyle(scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(name ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Overflow navigation rows

/// Destinations that do not fit a compact tab bar, rendered as account
/// rows (for the top of `StudioAccountSheet`'s `navRows`). Selecting one
/// routes and dismisses the sheet.
public struct StudioOverflowNavRows<Tag: Hashable>: View {
    private let destinations: [StudioNavDestination<Tag>]
    @Binding private var selection: Tag
    @Environment(\.dismiss) private var dismiss

    public init(destinations: [StudioNavDestination<Tag>], selection: Binding<Tag>) {
        self.destinations = destinations
        self._selection = selection
    }

    public var body: some View {
        ForEach(destinations) { destination in
            StudioAccountRow(
                systemImage: destination.tag == selection
                    ? destination.selectedSystemImage
                    : destination.systemImage,
                title: destination.title,
                detail: destination.count.map { "\($0)" }
            ) {
                selection = destination.tag
                dismiss()
            }
        }
    }
}
