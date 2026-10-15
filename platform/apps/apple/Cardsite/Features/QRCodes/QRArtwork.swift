import SwiftUI
import StudioKit
import CardsiteKit

/// A QR image as the server drew it: square, scaled without smoothing so
/// the modules stay sharp, over a checkerboard where the background is
/// transparent so the user can see that it is.
///
/// The PNG carries its own quiet zone and colours, so nothing is painted
/// behind it except the checkerboard.
struct QRArtwork: View {
    let png: Data?
    var isTransparent = false
    var isLoading = false
    /// Nothing to encode yet: shows a quiet placeholder instead of a skeleton.
    var isEmpty = false

    var body: some View {
        ZStack {
            if isTransparent, png != nil {
                QRCheckerboard()
            }
            if let png, let image = Image(pngData: png) {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .opacity(isLoading ? 0.45 : 1)
                    .animation(StudioAnimation.base, value: isLoading)
            } else if isEmpty {
                QREmptyArtwork()
            } else if isLoading {
                QRSkeleton()
            } else {
                QREmptyArtwork()
            }
            if isLoading, png != nil {
                ProgressView()
                    .controlSize(.regular)
                    .padding(StudioSpace.s3)
                    .background(Color.studioSurface, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: StudioRadius.xs, style: .continuous))
    }
}

/// A placeholder that breathes while the first image loads. With Reduce
/// Motion it holds still.
struct QRSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
            .fill(Color.studioSurface3)
            .opacity(isDim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: StudioDuration.slow * 2).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
            .accessibilityLabel(Text("Loading"))
    }
}

private struct QREmptyArtwork: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
            .strokeBorder(Color.studioBorderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .background(
                RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                    .fill(Color.studioSurface2)
            )
            .overlay {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.studioText4)
                    .padding(StudioSpace.s8)
                    .frame(maxWidth: StudioSpace.s16 * 2, maxHeight: StudioSpace.s16 * 2)
            }
            .accessibilityHidden(true)
    }
}

/// Two light tones in squares: the conventional sign for transparency. Fixed
/// light values, because it always sits on the white QR paper.
private struct QRCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile = StudioSpace.s2
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.StudioPalette.neutral0))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : tile
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)), with: .color(Color.StudioPalette.neutral200))
                    x += tile * 2
                }
                y += tile
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The server's stored image for a list row or detail.
struct QRImage: View {
    let code: QRCode

    var body: some View {
        QRArtwork(png: code.pngData)
    }
}

extension QRCode {
    var fileName: String {
        let base = Slug.suggestion(from: name)
        return (base.isEmpty ? "cardsite-qr-\(id)" : base) + ".png"
    }

    /// What a scan opens, worded for the copy button.
    var copyTitle: String {
        QRCodeCatalog.encodesURL(type) ? String(localized: "Copy Link") : String(localized: "Copy Content")
    }
}
