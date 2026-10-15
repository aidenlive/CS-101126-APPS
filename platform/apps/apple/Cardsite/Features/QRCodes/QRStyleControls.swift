import SwiftUI
import StudioKit

/// A one-tap colour scheme for a code. The hex values are the user's data
/// (what the generator draws), not app design, so they are strings that go
/// to the server as they are.
struct QRStylePreset: Identifiable, Equatable {
    let id: String
    let title: String
    let foreground: String
    let background: String

    /// Studio ink on white, white on ink, and ink on the Studio lime.
    static let all: [QRStylePreset] = [
        QRStylePreset(id: "ink-on-white", title: String(localized: "Ink on white"),
                      foreground: "#07090e", background: "#ffffff"),
        QRStylePreset(id: "white-on-ink", title: String(localized: "White on ink"),
                      foreground: "#ffffff", background: "#07090e"),
        QRStylePreset(id: "accent", title: String(localized: "Accent"),
                      foreground: "#07090e", background: "#66d632"),
    ]

    func matches(_ draft: QRCodeDraft) -> Bool {
        draft.foreground.lowercased() == foreground
            && draft.background.lowercased() == background
            && draft.transparency == 0
    }

    func apply(to draft: inout QRCodeDraft) {
        draft.foreground = foreground
        draft.background = background
        draft.transparency = 0
    }
}

/// How well two colours separate, as the WCAG contrast ratio (1…21).
/// Scanners need clear separation between modules and background.
enum QRContrast {
    static func ratio(_ first: String, _ second: String) -> Double? {
        guard let a = luminance(first), let b = luminance(second) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// True when the modules are lighter than the background, which some
    /// older readers don't decode.
    static func isInverted(foreground: String, background: String) -> Bool {
        guard let fg = luminance(foreground), let bg = luminance(background) else { return false }
        return fg > bg
    }

    static func luminance(_ hex: String) -> Double? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits.prefix(6), radix: 16) else { return nil }
        func channel(_ shift: UInt64) -> Double {
            let c = Double((value >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

/// The three presets as swatch tiles: each a small code drawn in its own
/// colours. Wraps to a column at accessibility sizes.
struct QRPresetRow: View {
    @Binding var draft: QRCodeDraft

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: StudioSpace.s3) { tiles }
            VStack(spacing: StudioSpace.s2) { tiles }
        }
        .padding(.vertical, StudioSpace.s1)
    }

    private var tiles: some View {
        ForEach(QRStylePreset.all) { preset in
            let isSelected = preset.matches(draft)
            Button {
                preset.apply(to: &draft)
            } label: {
                VStack(spacing: StudioSpace.s2) {
                    QRPresetSwatch(preset: preset, isSelected: isSelected)
                    Text(preset.title)
                        .studioText(.uiSm)
                        .foregroundStyle(isSelected ? Color.studioText : Color.studioText2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(StudioPressStyle(scale: 0.97))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(preset.title))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

private struct QRPresetSwatch: View {
    let preset: QRStylePreset
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
        Image(systemName: "qrcode")
            .resizable()
            .scaledToFit()
            .padding(StudioSpace.s3)
            .foregroundStyle(HexColor.color(from: preset.foreground) ?? Color.studioText)
            .frame(maxWidth: StudioSpace.s16, maxHeight: StudioSpace.s16)
            .aspectRatio(1, contentMode: .fit)
            .background(HexColor.color(from: preset.background) ?? Color.studioSurface, in: shape)
            .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
            .padding(StudioSpace.s1)
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.md + StudioSpace.s1, style: .continuous)
                    .strokeBorder(isSelected ? Color.studioAccentLine : Color.clear, lineWidth: 2)
            )
            .accessibilityHidden(true)
    }
}

/// A colour well as a tidy row: title, the hex in mono, the system well.
struct QRSwatchRow: View {
    let title: String
    @Binding var hex: String
    let fallback: Color

    var body: some View {
        ColorPicker(selection: HexColor.binding($hex, fallback: fallback), supportsOpacity: false) {
            HStack(spacing: StudioSpace.s2) {
                Text(title)
                    .foregroundStyle(Color.studioText)
                Spacer(minLength: StudioSpace.s2)
                Text(verbatim: hex.uppercased())
                    .studioText(.mono)
                    .foregroundStyle(Color.studioText3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(Text(verbatim: hex.uppercased()))
    }
}

/// A one-line warning under the colours when the code may not scan.
/// Call sites show it only when ``message(for:)`` is non-nil, so a form
/// gets no empty row.
struct QRContrastNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .studioText(.uiSm)
            .foregroundStyle(Color.studioWarning)
    }

    static func message(for draft: QRCodeDraft) -> String? {
        // Transparent backgrounds take the colour of whatever they're
        // printed on, so the ratio can't be judged here.
        guard draft.transparency == 0 else { return nil }
        if let ratio = QRContrast.ratio(draft.foreground, draft.background), ratio < 3 {
            return String(localized: "Low contrast: some phones may not scan this code.")
        }
        if QRContrast.isInverted(foreground: draft.foreground, background: draft.background) {
            return String(localized: "Light on dark: a few older scanners can’t read it.")
        }
        return nil
    }
}

#Preview("Presets") {
    @Previewable @State var draft = QRCodeDraft()
    Form {
        Section {
            QRPresetRow(draft: $draft)
        }
        Section {
            QRSwatchRow(title: "Foreground", hex: $draft.foreground, fallback: .studioText)
            QRSwatchRow(title: "Background", hex: $draft.background, fallback: .studioSurface)
            if let note = QRContrastNote.message(for: draft) {
                QRContrastNote(message: note)
            }
        }
    }
}
