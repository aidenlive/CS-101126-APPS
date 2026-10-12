import SwiftUI
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

    /// Caps readable width on iPad and Mac without affecting iPhone.
    func readableWidth(_ width: CGFloat = 640) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

extension Int {
    /// "1,234" in the user's locale.
    var grouped: String { formatted(.number) }

    /// A headline figure: grouped up to 99,999, then abbreviated ("128K"),
    /// as the web dashboard prints them.
    var figure: String {
        self >= 100_000 ? formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) : grouped
    }
}
