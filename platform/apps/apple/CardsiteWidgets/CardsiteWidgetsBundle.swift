import SwiftUI
import WidgetKit
import StudioKit

/// Cardsite's widgets for iPhone, iPad and Mac. They read the session the
/// app shares (`SharedSession`) and show a sign-in prompt until there is one.
@main
struct CardsiteWidgetsBundle: WidgetBundle {
    init() {
        // The widget extension is its own process: the Studio families must
        // be registered here too, or every `.studioText` falls back to the
        // system font.
        StudioFonts.register()
    }

    var body: some Widget {
        LinkTrafficWidget()
        QRCodeWidget()
    }
}
