#if os(macOS)
import SwiftUI
import AppKit
import StudioKit

/// Sets the minimum width of the Mac sidebar that `TabView(.sidebarAdaptable)`
/// draws. SwiftUI has no width API for that sidebar (only for
/// `NavigationSplitView` columns), and its default leaves titles such as
/// "Payment Links" truncated. Placed in the sidebar header; finds the
/// window's split view controller and sets the sidebar item's minimum
/// thickness, widening it once if it is narrower.
struct MacSidebarWidth: NSViewRepresentable {
    var minimum: CGFloat = StudioLayout.sidebarFull - StudioSpace.s8

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let minimum = minimum
        DispatchQueue.main.async {
            guard let root = view.window?.contentViewController,
                  let split = Self.splitController(in: root),
                  let sidebar = split.splitViewItems.first(where: { $0.behavior == .sidebar })
                    ?? split.splitViewItems.first
            else { return }
            if sidebar.minimumThickness < minimum {
                sidebar.minimumThickness = minimum
            }
            let width = sidebar.viewController.view.frame.width
            if width > 0, width < minimum, let index = split.splitViewItems.firstIndex(of: sidebar),
               index < split.splitView.arrangedSubviews.count - 1 {
                split.splitView.setPosition(minimum, ofDividerAt: index)
            }
        }
    }

    private static func splitController(in controller: NSViewController) -> NSSplitViewController? {
        if let split = controller as? NSSplitViewController { return split }
        for child in controller.children {
            if let found = splitController(in: child) { return found }
        }
        return nil
    }
}
#endif
