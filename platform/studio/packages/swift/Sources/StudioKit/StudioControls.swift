import SwiftUI

/*
 Controls.

 The atoms the web layer has had since v1 and the Swift package did
 not: segmented controls, toggles, checkboxes and radios, the search
 field, the select, the icon button, the FAB.

 Every one follows the same grammar as its CSS counterpart — press
 shrinks, the active segment takes a `surface` fill on a `surface-2`
 track, checked states fill with the accent and draw their glyph in
 `accent-ink`. Nothing here names a colour or a size that is not a
 token.
 */

// MARK: - Icon button

/// A 36pt round icon button. `label` is not optional by convention:
/// an icon-only control with no accessible name is a bug.
public struct StudioIconButton: View {
    private let systemImage: String
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    public init(
        systemImage: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .foregroundStyle(isActive ? Color.studioText : Color.studioText2)
                .background(isActive ? Color.studioAccentSoft : Color.clear, in: Circle())
                // The visual is 36pt; the hit area is the 44pt touch minimum.
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(StudioPressStyle(scale: 0.90))
        .accessibilityLabel(label)
    }
}

// MARK: - Compose / FAB

/// The one accent action in the sidebar. Collapses to its glyph in rail mode.
public struct StudioComposeButton: View {
    private let title: String
    private let systemImage: String
    private let isCompact: Bool
    private let action: () -> Void

    public init(
        _ title: String = "Compose",
        systemImage: String = "plus",
        isCompact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isCompact = isCompact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s2) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                if !isCompact { Text(title).studioText(.ui) }
            }
            .frame(maxWidth: isCompact ? 40 : .infinity)
            .frame(minHeight: 40)
            .foregroundStyle(Color.studioAccentInk)
            .background(Color.studioAccent, in: Capsule())
            .studioElevation(.raised)
        }
        .buttonStyle(StudioPressStyle())
        .accessibilityLabel(title)
    }
}

/// The mobile compose affordance. Last in the reading order, by design.
public struct StudioFab: View {
    private let systemImage: String
    private let label: String
    private let action: () -> Void

    public init(systemImage: String = "plus", label: String = "Compose", action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 52, height: 52)
                .foregroundStyle(Color.studioAccentInk)
                .background(Color.studioAccent, in: Circle())
                .studioElevation(.raised)
        }
        .buttonStyle(StudioPressStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

// MARK: - Segmented control

/// One option in a `StudioSegmented`.
public struct StudioSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    public let systemImage: String?

    public var id: Value { value }

    public init(value: Value, label: String, systemImage: String? = nil) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }
}

/// Segmented control. The active segment gets a `surface` fill on a
/// `surface-2` track, and the indicator springs between positions.
///
///     StudioSegmented(
///         label: "View",
///         selection: $view,
///         segments: [.init(value: .grid, label: "Grid", systemImage: "square.grid.2x2")]
///     )
public struct StudioSegmented<Value: Hashable>: View {
    private let label: String
    private let segments: [StudioSegment<Value>]
    private let iconsOnly: Bool
    @Binding private var selection: Value

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        label: String,
        selection: Binding<Value>,
        segments: [StudioSegment<Value>],
        iconsOnly: Bool = false
    ) {
        self.label = label
        self._selection = selection
        self.segments = segments
        self.iconsOnly = iconsOnly
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                Button {
                    // Reduce Motion: the indicator jumps rather than springs.
                    withAnimation(reduceMotion ? nil : StudioAnimation.spring) { selection = segment.value }
                } label: {
                    HStack(spacing: StudioSpace.s2) {
                        if let symbol = segment.systemImage {
                            Image(systemName: symbol).font(.system(size: 14))
                        }
                        if !iconsOnly { Text(segment.label).studioText(.uiSm) }
                    }
                    .frame(maxWidth: iconsOnly ? 36 : .infinity)
                    .frame(minHeight: 32)
                    .foregroundStyle(selection == segment.value ? Color.studioText : Color.studioText2)
                    .background {
                        if selection == segment.value {
                            Capsule()
                                .fill(Color.studioSurface)
                                .matchedGeometryEffect(id: "studio.segment", in: indicator)
                                .studioElevation(.flat)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.label)
                .accessibilityAddTraits(selection == segment.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.studioSurface2, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.studioBorder, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Toggle row

/// Label + optional helper on the left, switch on the right. The whole
/// row is the hit target, which is how the web `.lk-choice` behaves.
public struct StudioToggleRow: View {
    private let label: String
    private let help: String?
    @Binding private var isOn: Bool

    public init(_ label: String, help: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.help = help
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).studioText(.ui).foregroundStyle(Color.studioText)
                if let help {
                    Text(help).studioText(.uiSm).foregroundStyle(Color.studioText3)
                }
            }
        }
        // A switch on every platform: the macOS default is a checkbox.
        .toggleStyle(.switch)
        .tint(.studioAccent)
        .frame(minHeight: 44)
    }
}

// MARK: - Choice row (checkbox / radio)

public enum StudioChoiceStyle {
    case checkbox
    case radio
}

/// A checkbox or radio row.
///
/// SwiftUI has no styled checkbox on iOS, so the glyph is drawn from
/// tokens the same way the CSS draws it: a 20pt `xs`-radius square or
/// circle, hairline border, accent fill with an `accent-ink` mark when
/// checked. The row is the hit target and carries the a11y traits.
public struct StudioChoiceRow: View {
    private let label: String
    private let help: String?
    private let style: StudioChoiceStyle
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        _ label: String,
        help: String? = nil,
        style: StudioChoiceStyle = .checkbox,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.help = help
        self.style = style
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: StudioSpace.s3) {
                glyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).studioText(.ui).foregroundStyle(Color.studioText)
                    if let help {
                        Text(help)
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(help ?? "")
    }

    @ViewBuilder
    private var glyph: some View {
        ZStack {
            shape
                .fill(isSelected ? Color.studioAccent : Color.studioSurface)
            shape
                .strokeBorder(isSelected ? Color.studioAccentLine : Color.studioBorderStrong, lineWidth: 0.5)

            if isSelected {
                switch style {
                case .checkbox:
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.studioAccentInk)
                case .radio:
                    Circle()
                        .fill(Color.studioAccentInk)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .frame(width: 20, height: 20)
        .padding(.top, 2)
        .animation(StudioAnimation.base, value: isSelected)
    }

    private var shape: some InsettableShape {
        // Both branches must be one type, so the square is a rounded
        // rectangle and the circle is one with a pill radius.
        RoundedRectangle(
            cornerRadius: style == .checkbox ? StudioRadius.xs : 10,
            style: .continuous
        )
    }
}

/// Groups choice rows under a legend, the way `fieldset` + `legend` do.
public struct StudioChoiceGroup<Content: View>: View {
    private let legend: String
    private let content: Content

    public init(_ legend: String, @ViewBuilder content: () -> Content) {
        self.legend = legend
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(legend)
                .studioText(.uiSm)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText)
                .padding(.bottom, StudioSpace.s2)
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(legend)
    }
}

// MARK: - Search field

/// The pill search field with its leading magnifier.
public struct StudioSearchField: View {
    private let placeholder: String
    private let label: String
    @Binding private var text: String

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Search\u{2026}",
        label: String = "Search"
    ) {
        self._text = text
        self.placeholder = placeholder
        self.label = label
    }

    public var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.studioText3)

            TextField(placeholder, text: $text)
                // Plain, so macOS does not draw its own bezel inside the pill.
                .textFieldStyle(.plain)
                .studioText(.ui)
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                StudioIconButton(systemImage: "xmark.circle.fill", label: "Clear search") {
                    text = ""
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(isFocused ? Color.studioSurface : Color.studioSurface2, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                isFocused ? Color.studioAccentLine : Color.studioBorder,
                lineWidth: isFocused ? 1 : 0.5
            )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.studioAccentGlow, lineWidth: isFocused ? 3 : 0)
                .padding(-2)
        )
        .animation(StudioAnimation.base, value: isFocused)
        .accessibilityLabel(label)
    }
}

// MARK: - Select

/// A select. Uses the platform menu rather than a custom listbox —
/// on iOS the native menu IS the correct control, and it inherits
/// dismissal, keyboard and VoiceOver behaviour for free.
public struct StudioSelect<Value: Hashable>: View {
    private let label: String
    private let options: [StudioSegment<Value>]
    @Binding private var selection: Value

    public init(label: String, selection: Binding<Value>, options: [StudioSegment<Value>]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if selection == option.value {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: StudioSpace.s3) {
                Text(current).studioText(.ui).foregroundStyle(Color.studioText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.studioText3)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .contentShape(RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .fill(Color.studioSurface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .strokeBorder(Color.studioBorder, lineWidth: 0.5)
            )
        }
        // Our label draws the field and its chevron, so on macOS the menu
        // must not add a bordered pop-up button and indicator around it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }

    private var current: String {
        options.first { $0.value == selection }?.label ?? label
    }
}

// MARK: - Keyboard chip

/// The `kbd` chip, for menus and shortcut tables.
public struct StudioKbd: View {
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .studioText(.mono)
            .foregroundStyle(Color.studioText3)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: StudioRadius.xs, style: .continuous)
                    .fill(Color.studioSurface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.xs, style: .continuous)
                    .strokeBorder(Color.studioBorder, lineWidth: 0.5)
            )
    }
}
