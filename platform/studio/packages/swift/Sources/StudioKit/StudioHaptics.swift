import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/*
 Haptics.

 One enum-typed surface, gated behind a user preference, fired near the
 user's action and never stacked. Call sites need no platform checks:

 · iPhone / iPad: UIKit feedback generators.
 · Apple Vision Pro: a no-op (UIKit's feedback generators aren't there).
 · Mac: `NSHapticFeedbackManager`, which plays on a Force Touch trackpad
   and is silent everywhere else (the system decides, not us).
 · Anything without haptic hardware: a no-op.

 Install once at the root:

     @StateObject private var haptics = StudioHaptics()
     …
     .environment(\.studioHaptics, haptics)

 then, at the moment of the action:

     @Environment(\.studioHaptics) private var haptics
     haptics.play(.success)

 Rules: one feedback per user action; `.selection` for switching among
 peers; `.success` only on something that actually completed. Haptics on
 scroll, appearance, or anything the user did not initiate are the fast
 route to a phone people turn the feature off on.

 Concurrency: the class is deliberately NOT `@MainActor`. An
 `EnvironmentKey.defaultValue` is a lazy static initialised on whatever
 thread touches it first, so a main-actor default would cross isolation.
 The class holds one Bool and no UIKit state; only FIRING must be on the
 main actor, so `play` hops precisely there.
 */
public final class StudioHaptics: ObservableObject, @unchecked Sendable {
    /// Bound to the app's haptics preference.
    @Published public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public enum Feedback: Sendable {
        /// Moving between peers: tabs, segments, chips.
        case selection
        /// A press or a pick.
        case light
        /// Something completed.
        case success
        /// A destructive or reversible-but-notable action.
        case warning
        /// Something failed.
        case error
    }

    public func play(_ feedback: Feedback) {
        guard isEnabled else { return }
        // Call sites are SwiftUI actions, so this is virtually always the
        // main thread already: take the free path, hop only when it isn't.
        // A haptic that arrives a runloop late is worse than none.
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.fire(feedback) }
        } else {
            Task { @MainActor in Self.fire(feedback) }
        }
    }

    @MainActor
    private static func fire(_ feedback: Feedback) {
        #if canImport(UIKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
        switch feedback {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #elseif os(macOS)
        // The trackpad has three patterns. Alignment is the "snapped into
        // place" tick (selection); level change marks a completed step.
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch feedback {
        case .selection: pattern = .alignment
        case .success: pattern = .levelChange
        case .light, .warning, .error: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        #endif
    }
}

private struct StudioHapticsKey: EnvironmentKey {
    /// Nonisolated, so the lazy static is legal from any thread. The
    /// instance plays until an app injects its own bound to a preference.
    static let defaultValue = StudioHaptics()
}

public extension EnvironmentValues {
    var studioHaptics: StudioHaptics {
        get { self[StudioHapticsKey.self] }
        set { self[StudioHapticsKey.self] = newValue }
    }
}
