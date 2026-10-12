import SwiftUI
import StudioKit
import CoreTransferable
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Small platform seams, kept in one place.
enum Pasteboard {
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

extension Image {
    /// An image from PNG bytes, or nil if they don't decode.
    init?(pngData: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: pngData) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: pngData) else { return nil }
        self.init(nsImage: image)
        #else
        return nil
        #endif
    }
}

/// A PNG that can be shared or dragged as a file.
struct PNGFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.name }
    }
}

enum Haptics {
    @MainActor
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

extension View {
    /// Form fields: no autocapitalisation or autocorrection for addresses,
    /// emails and URLs.
    func plainEntry() -> some View {
        #if os(iOS) || os(visionOS)
        return self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        return self.autocorrectionDisabled()
        #endif
    }

    /// Caps a page's content at one of the app's measures on iPad and Mac,
    /// centred, without affecting iPhone. For a `Form` or `List`, use
    /// ``studioForm(measure:)`` / ``studioList(measure:)`` instead, which
    /// cap the rows and leave the scroll indicator at the window edge.
    func readableWidth(_ measure: CardsiteMeasure = .reading) -> some View {
        frame(maxWidth: measure.width).frame(maxWidth: .infinity)
    }
}

/// The app's content widths. Every capped surface uses one of these, so
/// iPad and Mac pages line up as you move between them.
///
/// · `dashboard`: Home, Statistics and the Uploads gallery: three columns
///   of cards, no wider.
/// · `reading`: forms, lists and detail pages (StudioKit's rhythm measure).
/// · `sheet`: a sheet's single column and the full-area empty and error states.
/// · `narrow`: the sign-in card, a phone-sized preview, a QR code's artwork.
enum CardsiteMeasure: Sendable {
    case dashboard
    case reading
    case sheet
    case narrow

    var width: CGFloat {
        switch self {
        case .dashboard: return 1120
        case .reading: return StudioComposition.rhythmMeasure
        case .sheet: return 560
        case .narrow: return 440
        }
    }
}

extension Int {
    /// "1,234" in the user's locale. Row and table figures: list rows,
    /// breakdown tables, editor rows.
    var grouped: String { formatted(.number) }

    /// A display figure (stat tiles, headline numbers, a detail header):
    /// grouped up to 99,999, then abbreviated ("128K"), as the web
    /// dashboard prints them.
    var figure: String {
        self >= 100_000 ? formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) : grouped
    }
}

/// "5 minutes ago", kept current: re-renders each minute, so a row left on
/// screen doesn't go stale.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text(date.formatted(.relative(presentation: .named)))
        }
    }
}
