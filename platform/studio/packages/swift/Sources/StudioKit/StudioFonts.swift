import SwiftUI
import CoreText

/// Registers the four bundled families with Core Text.
///
/// SwiftUI can only resolve a font by name once it has been registered, and
/// fonts inside a Swift package are not registered automatically. Call this
/// once, as early as possible — `StudioFonts.register()` in your `App.init()`.
///
/// It is safe to call more than once; already-registered files are ignored.
public enum StudioFonts {

    /// Every font file bundled with the package.
    private static let files: [String] = [
        "Bounded-Variable", "EditorialNew-Italic", "SpaceGrotesk-Variable",
        "Certia-Thin", "Certia-Thin-Italic",
        "Certia-Light", "Certia-Light-Italic",
        "Certia-Regular", "Certia-Regular-Italic",
        "Certia-Medium", "Certia-Medium-Italic",
        "Certia-SemiBold", "Certia-SemiBold-Italic",
        "Certia-Bold", "Certia-Bold-Italic",
        "Certia-ExtraBold", "Certia-ExtraBold-Italic",
        "Certia-Black", "Certia-Black-Italic",
    ]

    /// One-time registration.
    ///
    /// A static `let` is lazy and its initialiser is guaranteed to run exactly
    /// once, even from several threads — the compiler wraps it in `swift_once`.
    /// That gives idempotency for free and, unlike a mutable `static var`,
    /// stays legal under Swift 6 strict-concurrency checking.
    private static let registration: Void = {
        for name in files {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf")
                ?? Bundle.module.url(forResource: name, withExtension: "otf")

            guard let url else {
                assertionFailure("StudioKit: font \(name) is missing from the bundle")
                continue
            }

            var error: Unmanaged<CFError>?
            // .process places resources at the bundle root, so a flat lookup is correct.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // A duplicate registration is expected if the host app also
                // ships these files; anything else is worth surfacing in debug.
                #if DEBUG
                if let error = error?.takeUnretainedValue() {
                    let code = CFErrorGetCode(error)
                    let alreadyRegistered = code == CTFontManagerError.alreadyRegistered.rawValue
                    if !alreadyRegistered {
                        print("StudioKit: could not register \(name) — \(error)")
                    }
                }
                #endif
            }
        }
    }()

    /// Registers the bundled families. Safe to call from anywhere, any number
    /// of times; only the first call does work.
    public static func register() {
        _ = registration
    }
}
