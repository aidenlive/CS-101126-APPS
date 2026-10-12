import SwiftUI

/*
 Feedback.

 The toast, and the object that owns them.

 Same contract as `Studio.toast()` on the web and `useToast()` in
 React: a glass pill, bottom centre, spring rise, auto-dismiss, and an
 announcement to assistive tech. On the web errors announce assertively
 and anything else politely; here every toast posts one standard
 VoiceOver announcement (no priority attribute yet). With Reduce Motion
 on, toasts fade instead of rising on a spring.
 */

/// A queued toast.
public struct StudioToast: Identifiable, Equatable {
    public enum Variant {
        case neutral, success, error

        var symbol: String {
            switch self {
            case .neutral: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }

        var ink: Color {
            switch self {
            case .neutral: return .studioText2
            case .success: return .studioSuccess
            case .error: return .studioError
            }
        }
    }

    public let id = UUID()
    public let message: String
    public let variant: Variant

    public init(_ message: String, variant: Variant = .neutral) {
        self.message = message
        self.variant = variant
    }
}

/// Owns the toast queue for a scene.
///
///     @StateObject private var toasts = StudioToastCenter()
///     …
///     .studioToasts(toasts)
///     …
///     toasts.show("Collection saved", variant: .success)
@MainActor
public final class StudioToastCenter: ObservableObject {
    @Published public private(set) var toasts: [StudioToast] = []

    private let duration: Double

    public init(duration: Double = 4) {
        self.duration = duration
    }

    public func show(_ message: String, variant: StudioToast.Variant = .neutral) {
        let toast = StudioToast(message, variant: variant)
        withAnimation(StudioAnimation.spring) {
            toasts.append(toast)
        }
        // A toast is visual only; VoiceOver would otherwise never hear it.
        AccessibilityNotification.Announcement(message).post()
        guard duration > 0 else { return }
        // Capture `duration` by value: reading it through `self` inside a
        // `[weak self]` Task is the Swift 6 implicit-self error.
        Task { [weak self, duration] in
            try? await Task.sleep(for: .seconds(duration))
            self?.dismiss(toast)
        }
    }

    public func dismiss(_ toast: StudioToast) {
        withAnimation(StudioAnimation.base) {
            toasts.removeAll { $0.id == toast.id }
        }
    }
}

/// One toast pill.
public struct StudioToastView: View {
    private let toast: StudioToast

    public init(_ toast: StudioToast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: toast.variant.symbol)
                .font(.system(size: 17))
                .foregroundStyle(toast.variant.ink)
            Text(toast.message)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .studioGlass()
        .accessibilityElement(children: .combine)
    }
}

public extension View {

    /// Presents the centre's toasts above this view, bottom centre,
    /// clear of the tab pill and the home indicator.
    func studioToasts(_ center: StudioToastCenter) -> some View {
        modifier(StudioToastLayer(center: center))
    }
}

private struct StudioToastLayer: ViewModifier {
    @ObservedObject var center: StudioToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                VStack(spacing: StudioSpace.s2) {
                    ForEach(center.toasts) { toast in
                        StudioToastView(toast)
                            .onTapGesture { center.dismiss(toast) }
                            .transition(
                                reduceMotion
                                    ? AnyTransition.opacity
                                    : AnyTransition.move(edge: .bottom).combined(with: .opacity)
                            )
                    }
                }
                // Clear the floating tab pill, exactly as the CSS does
                // below 720px: inset + pill height + one gap.
                .padding(.bottom, StudioLayout.floatInset + 52 + StudioSpace.s2)
                // This overrides the centre's `withAnimation(spring)`: under
                // Reduce Motion the change is a short fade, never a spring.
                .animation(reduceMotion ? StudioAnimation.base : StudioAnimation.spring, value: center.toasts)
                .accessibilityAddTraits(.isStaticText)
            }
    }
}
