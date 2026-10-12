import SwiftUI

/*
 Surfaces.

 Page heads, section headers, tables, list rows and the modal — the
 compositions the web layer ships as `.lk-pagehead`, `.lk-table`,
 `.lk-modal` and the three list shapes.

 The list shapes are worth stating plainly, because they are the same
 three on every platform: ROW (thumbnail + title + caption), TILE
 (square media + two-line title) and CARD (16:10 media + kicker +
 display title + meta). Everything else is one of those with different
 content.
 */

// MARK: - Page head

/// Kicker + two-tone display title on the left, actions on the right.
/// Stacks below tablet; side by side from there up — the same rule the
/// stylesheet applies at 720px.
public struct StudioPageHead<Actions: View>: View {
    private let kicker: String?
    private let title: String
    private let accent: String
    private let actions: Actions

    @Environment(\.studioViewport) private var viewport

    public init(
        kicker: String? = nil,
        title: String,
        accent: String = "",
        @ViewBuilder actions: () -> Actions
    ) {
        self.kicker = kicker
        self.title = title
        self.accent = accent
        self.actions = actions()
    }

    public var body: some View {
        let text = VStack(alignment: .leading, spacing: StudioSpace.s3) {
            if let kicker { StudioKicker(kicker) }
            if accent.isEmpty {
                Text(title).studioText(.display)
            } else {
                StudioTwoToneTitle(title, accent: accent)
            }
        }

        return Group {
            if viewport == .compact {
                VStack(alignment: .leading, spacing: StudioSpace.s4) {
                    text
                    HStack(spacing: StudioSpace.s3) { actions }
                }
            } else {
                HStack(alignment: .bottom, spacing: StudioSpace.s4) {
                    text
                    Spacer(minLength: StudioSpace.s6)
                    HStack(spacing: StudioSpace.s3) { actions }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension StudioPageHead where Actions == EmptyView {
    init(kicker: String? = nil, title: String, accent: String = "") {
        self.init(kicker: kicker, title: title, accent: accent) { EmptyView() }
    }
}

/// A label above a group of components. The gallery is built from these.
public struct StudioSectionHeader: View {
    private let title: String
    private let note: String?

    public init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(Color.studioText3)
            if let note {
                Text(note)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - List shapes

/// ROW — 64pt media, title, caption meta. The densest of the three.
public struct StudioListRow: View {
    private let title: String
    private let meta: String
    private let systemImage: String
    private let isSelected: Bool
    private let action: (() -> Void)?

    public init(
        title: String,
        meta: String,
        systemImage: String,
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.meta = meta
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let content = HStack(spacing: StudioSpace.s4) {
            RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                .fill(Color.studioSurface3)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.studioText3)
                )

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(title).studioText(.ui).foregroundStyle(Color.studioText)
                Text(meta).studioText(.meta).foregroundStyle(Color.studioText3)
            }

            Spacer(minLength: 0)
        }
        .padding(StudioSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .fill(isSelected ? Color.studioAccentSoft : Color.studioSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .strokeBorder(isSelected ? Color.studioAccentLine : Color.studioBorder, lineWidth: 0.5)
        )
        .studioElevation(.flat)

        return Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(StudioPressStyle(scale: 0.98))
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// CARD — 16:10 media, kicker, display title, meta. The showcase shape.
public struct StudioMediaCard: View {
    private let kicker: String
    private let title: String
    private let meta: String
    private let systemImage: String
    private let action: (() -> Void)?

    public init(
        kicker: String,
        title: String,
        meta: String,
        systemImage: String,
        action: (() -> Void)? = nil
    ) {
        self.kicker = kicker
        self.title = title
        self.meta = meta
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.studioSurface3)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 26))
                        .foregroundStyle(Color.studioText4)
                )

            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                StudioKicker(kicker)
                Text(title).studioText(.titleSm).foregroundStyle(Color.studioText)
                Text(meta).studioText(.meta).foregroundStyle(Color.studioText3)
            }
            .padding(StudioSpace.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.studioSurface)
        .clipShape(RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
        )
        .studioElevation(.flat)

        return Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(StudioPressStyle(scale: 0.98))
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Table

/// A column in a `StudioTable`.
public struct StudioColumn<Row>: Identifiable {
    public let id: String
    public let title: String
    public let isNumeric: Bool
    public let value: (Row) -> String

    public init(id: String, title: String, isNumeric: Bool = false, value: @escaping (Row) -> String) {
        self.id = id
        self.title = title
        self.isNumeric = isNumeric
        self.value = value
    }
}

/// A data table.
///
/// Below tablet a real table becomes a horizontal-scroll trap, so the
/// same rows render as stacked label/value pairs instead — the data is
/// identical, the shape follows the width. The web layer solves this
/// with `overflow-x`, which is the right answer for a pointer and the
/// wrong one for a thumb.
public struct StudioTable<Row: Identifiable>: View {
    private let caption: String
    private let columns: [StudioColumn<Row>]
    private let rows: [Row]

    @Environment(\.studioViewport) private var viewport

    public init(caption: String, columns: [StudioColumn<Row>], rows: [Row]) {
        self.caption = caption
        self.columns = columns
        self.rows = rows
    }

    public var body: some View {
        Group {
            if viewport == .compact { stacked } else { grid }
        }
        .accessibilityLabel(caption)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: StudioSpace.s4) {
                ForEach(columns) { column in
                    Text(column.title)
                        .studioText(.label)
                        .foregroundStyle(Color.studioText3)
                        .frame(maxWidth: .infinity, alignment: column.isNumeric ? .trailing : .leading)
                }
            }
            .padding(.horizontal, StudioSpace.s4)
            .padding(.vertical, StudioSpace.s3)

            Divider().overlay(Color.studioBorder)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: StudioSpace.s4) {
                    ForEach(columns) { column in
                        Text(column.value(row))
                            .studioText(column.isNumeric ? .mono : .ui)
                            .foregroundStyle(Color.studioText2)
                            .frame(maxWidth: .infinity, alignment: column.isNumeric ? .trailing : .leading)
                    }
                }
                .padding(.horizontal, StudioSpace.s4)
                .padding(.vertical, StudioSpace.s3)
                .accessibilityElement(children: .combine)

                if index < rows.count - 1 {
                    Divider().overlay(Color.studioBorder)
                }
            }
        }
    }

    private var stacked: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: StudioSpace.s2) {
                    ForEach(columns) { column in
                        HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                            Text(column.title)
                                .studioText(.label)
                                .foregroundStyle(Color.studioText3)
                            Spacer(minLength: StudioSpace.s4)
                            Text(column.value(row))
                                .studioText(column.isNumeric ? .mono : .ui)
                                .foregroundStyle(Color.studioText2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(StudioSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if index < rows.count - 1 {
                    Divider().overlay(Color.studioBorder)
                }
            }
        }
    }
}

// MARK: - Modal

/// A confirm dialog.
///
/// Presented as a sheet so the system owns the scrim, the focus and the
/// dismiss gesture; the card inside is the Studio one. Destructive
/// confirms pair a ghost cancel with an error-fill action, and the
/// destructive button is never the one that gets focus first.
public struct StudioConfirmDialog: View {
    private let title: String
    private let message: String
    private let confirmTitle: String
    private let cancelTitle: String
    private let isDestructive: Bool
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            Text(title)
                .studioText(.titleSm)
                .foregroundStyle(Color.studioText)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .studioText(.body)
                .foregroundStyle(Color.studioText2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: StudioSpace.s3) {
                Spacer(minLength: 0)
                StudioButton(cancelTitle, action: onCancel)
                StudioButton(
                    confirmTitle,
                    variant: isDestructive ? .destructive : .primary,
                    action: onConfirm
                )
            }
        }
        .padding(StudioSpace.s6)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .fill(Color.studioSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
        )
        .padding(StudioSpace.s5)
        .accessibilityAddTraits(.isModal)
    }
}
