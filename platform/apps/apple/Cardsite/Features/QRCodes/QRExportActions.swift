import SwiftUI
import UniformTypeIdentifiers
import StudioKit

/// The viewer's action strip, as under a photo: Share, Save Image, Copy
/// Link (or Copy Content) and Edit, as equal tiles. Four across where they
/// fit, two by two on a narrow screen, one column at accessibility sizes.
struct QRExportActions: View {
    let png: Data
    let fileName: String
    let title: String
    let copyText: String?
    let copyTitle: String
    var edit: (() -> Void)? = nil

    @State private var isExporting = false
    @State private var copied = false
    @State private var exportError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StudioSpace.s2) { tiles }
                Grid(horizontalSpacing: StudioSpace.s2, verticalSpacing: StudioSpace.s2) {
                    GridRow { shareTile; saveTile }
                    if copyTile != nil || edit != nil {
                        GridRow {
                            if let copyTile { copyTile }
                            if let edit { editTile(edit) }
                        }
                    }
                }
                VStack(spacing: StudioSpace.s2) { tiles }
            }
            FormErrorText(message: exportError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qrImageExporter(isPresented: $isExporting, png: png, fileName: fileName, error: $exportError)
    }

    @ViewBuilder
    private var tiles: some View {
        shareTile
        saveTile
        if let copyTile { copyTile }
        if let edit { editTile(edit) }
    }

    private var shareTile: some View {
        ShareLink(item: PNGFile(data: png, name: fileName),
                  preview: SharePreview(title, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(QRActionTileStyle())
        .accessibilityLabel(Text("Share Image"))
    }

    private var saveTile: some View {
        Button {
            isExporting = true
        } label: {
            Label("Save Image", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(QRActionTileStyle())
        .keyboardShortcut("s", modifiers: [.command, .shift])
    }

    private var copyTile: AnyView? {
        guard let copyText, !copyText.isEmpty else { return nil }
        return AnyView(
            Button {
                Pasteboard.copy(copyText)
                Haptics.success()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? String(localized: "Copied") : copyTitle,
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(QRActionTileStyle())
            .accessibilityValue(copied ? Text("Copied") : Text(""))
        )
    }

    private func editTile(_ edit: @escaping () -> Void) -> some View {
        Button(action: edit) {
            Label("Edit", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(QRActionTileStyle())
        .keyboardShortcut("e", modifiers: .command)
    }
}

/// An action tile: symbol over a short title on an opaque Studio surface.
/// Content layer, so no glass.
struct QRActionTileStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
        configuration.label
            .labelStyle(QRActionTileLabelStyle())
            .frame(maxWidth: .infinity, minHeight: StudioLayout.tapTarget)
            .padding(.vertical, StudioSpace.s3)
            .padding(.horizontal, StudioSpace.s2)
            .background(configuration.isPressed ? Color.studioSurface2 : Color.studioSurface, in: shape)
            .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : StudioAnimation.press, value: configuration.isPressed)
    }
}

private struct QRActionTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: StudioSpace.s2) {
            configuration.icon
                .font(.title3)
                .foregroundStyle(Color.studioText)
                .accessibilityHidden(true)
            configuration.title
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

extension View {
    /// Saves the PNG to a file the user picks. A failure lands in `error`.
    func qrImageExporter(isPresented: Binding<Bool>, png: Data?, fileName: String, error: Binding<String?>) -> some View {
        fileExporter(
            isPresented: isPresented,
            item: png.map { PNGFile(data: $0, name: fileName) },
            contentTypes: [.png],
            defaultFilename: fileName
        ) { result in
            switch result {
            case .failure(let failure):
                error.wrappedValue = failure.localizedDescription
            case .success:
                error.wrappedValue = nil
                Haptics.success()
            }
        }
    }
}

#Preview("Actions") {
    QRExportActions(png: Data(), fileName: "menu.png", title: "Window menu",
                    copyText: "https://example.com/menu", copyTitle: "Copy Link", edit: {})
        .padding(StudioSpace.s6)
        .background(Color.studioBg)
}
