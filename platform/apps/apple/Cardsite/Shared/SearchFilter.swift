import SwiftUI

extension View {
    /// A list's own filter field: `searchable` with a "Filter …" prompt,
    /// minimized on OS 26 and later so it collapses to the toolbar's
    /// magnifier instead of standing as a full field. That keeps a list
    /// filter from reading as the app's Search tab, which searches
    /// everything.
    ///
    /// `searchToolbarBehavior(_:)` and `SearchToolbarBehavior.minimize` are
    /// iOS, iPadOS, macOS and visionOS 26.0+ (Apple's SwiftUI reference,
    /// checked 2026-10-15). Earlier systems keep the standard field.
    ///
    ///     .searchFilter(text: $model.searchText, prompt: Text("Filter links"))
    func searchFilter(text: Binding<String>, prompt: Text) -> some View {
        searchable(text: text, prompt: prompt)
            .modifier(MinimizedSearchToolbar())
    }
}

/// Applied after `searchable`, as the modifier's documentation requires.
private struct MinimizedSearchToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.searchToolbarBehavior(.minimize)
        } else {
            content
        }
    }
}
