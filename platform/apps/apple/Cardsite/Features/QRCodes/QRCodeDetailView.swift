import SwiftUI
import StudioKit
import CardsiteKit

/// One code, presented like a photo: the code large on the white stage,
/// its name in the display face, what it points to as a row, then Share,
/// Save Image, Copy and Edit. Present shows it full screen on white, for
/// holding up to someone's camera.
struct QRCodeDetailView: View {
    let code: QRCode
    let typeLabel: String
    let edit: () -> Void
    let requestDelete: () -> Void

    @State private var isPresenting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                stage
                    .padding(.horizontal, StudioSpace.s6)
                    .padding(.vertical, StudioSpace.s8)
                    .frame(maxWidth: .infinity)
                    .background(Color.studioCanvasBg)

                VStack(alignment: .leading, spacing: StudioSpace.s6) {
                    QRTargetRow(code: code)

                    if let png = code.pngData {
                        QRExportActions(png: png, fileName: code.fileName, title: code.name,
                                        copyText: code.target, copyTitle: code.copyTitle, edit: edit)
                    } else {
                        // No stored image: editing regenerates one.
                        StudioButton(String(localized: "Edit"), systemImage: "slider.horizontal.3",
                                     variant: .outline, action: edit)
                    }

                    // The one irreversible action stays in the body, as the
                    // link and resource details keep it.
                    HStack(spacing: StudioSpace.s2) {
                        StudioButton(ResourceVerb.delete.title, systemImage: ResourceVerb.delete.systemImage,
                                     variant: .danger, action: requestDelete)
                        Spacer(minLength: 0)
                    }
                }
                .padding(StudioSpace.s6)
                .readableWidth(.sheet)
            }
        }
        .background(Color.studioBg)
        .navigationTitle(code.name)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresenting = true
                } label: {
                    Label("Present", systemImage: "qrcode.viewfinder")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(code.pngData == nil)
                .accessibilityHint(Text("Shows the code full screen for scanning"))
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isPresenting) {
            QRPresentView(code: code)
        }
        #else
        .sheet(isPresented: $isPresenting) {
            QRPresentView(code: code)
                .frame(minWidth: CardsiteMeasure.sheet.width, minHeight: CardsiteMeasure.sheet.width)
        }
        #endif
    }

    private var stage: some View {
        QRStage(
            png: code.pngData,
            title: code.name,
            typeLabel: typeLabel,
            typeSymbol: QRCodeCatalog.symbol(for: code.type),
            scale: .large,
            accessibilityLabel: Text("QR code for \(code.name)"),
            accessibilityValue: Text(verbatim: code.target ?? "")
        ) {
            if let created = code.createdAt {
                Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if code.pngData != nil { isPresenting = true }
        }
        .accessibilityAction(named: Text("Present")) {
            if code.pngData != nil { isPresenting = true }
        }
    }
}

/// What a scan opens or reads, as one row. A web address is a link that
/// opens in the browser; anything else (WiFi, a contact card) is selectable
/// text.
private struct QRTargetRow: View {
    let code: QRCode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
        Group {
            if let url {
                Link(destination: url) {
                    row(trailing: "arrow.up.right")
                }
                .buttonStyle(StudioPressStyle(scale: 0.99))
                .accessibilityHint(Text("Opens in your browser"))
            } else {
                row(trailing: nil)
                    .accessibilityElement(children: .combine)
            }
        }
        .background(Color.studioSurface, in: shape)
        .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
    }

    private var url: URL? {
        guard QRCodeCatalog.encodesURL(code.type), let target = code.target, !target.isEmpty,
              let url = URL(string: target), url.scheme != nil else { return nil }
        return url
    }

    private func row(trailing: String?) -> some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Image(systemName: QRCodeCatalog.symbol(for: code.type))
                .foregroundStyle(Color.studioText2)
                .frame(minWidth: StudioSpace.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(QRCodeCatalog.encodesURL(code.type) ? String(localized: "Opens") : String(localized: "Encodes"))
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                targetText
                if code.type == QRCodeCatalog.dynamicURLType {
                    Text("A dynamic code: change the link’s destination and printed copies follow it.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.studioText3)
                    .accessibilityHidden(true)
            }
        }
        .padding(StudioSpace.s4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var targetText: some View {
        if let target = code.target, !target.isEmpty {
            if url != nil {
                Text(verbatim: target)
                    .studioText(.body)
                    .foregroundStyle(Color.studioText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            } else {
                Text(verbatim: target)
                    .studioText(.mono)
                    .foregroundStyle(Color.studioText2)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
        } else {
            Text("Nothing recorded")
                .studioText(.body)
                .foregroundStyle(Color.studioText3)
        }
    }
}

/// Present mode: the code as large as the screen allows on plain white, its
/// name underneath, nothing else. The screen stays awake while it shows.
/// Close with ✕, Escape, or a tap anywhere.
struct QRPresentView: View {
    let code: QRCode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.StudioPalette.neutral0
                .ignoresSafeArea()

            VStack(spacing: StudioSpace.s6) {
                QRArtwork(png: code.pngData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("QR code for \(code.name)"))
                    .accessibilityValue(Text(verbatim: code.target ?? ""))
                    .accessibilityAddTraits(.isImage)
                Text(code.name)
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(StudioSpace.s10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: StudioLayout.tapTarget, minHeight: StudioLayout.tapTarget)
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .keyboardShortcut(.cancelAction)
            .padding(StudioSpace.s4)
            .accessibilityLabel(Text("Close"))
        }
        // White paper whatever the system appearance: tokens inside resolve
        // their light values, so the name reads as ink on white.
        .environment(\.colorScheme, .light)
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }
}

#Preview("Detail") {
    NavigationStack {
        QRCodeDetailView(code: QRCodesPreviewData.codes[0], typeLabel: "URL", edit: {}, requestDelete: {})
    }
}

#Preview("WiFi detail") {
    NavigationStack {
        QRCodeDetailView(code: QRCodesPreviewData.codes[1], typeLabel: "WiFi", edit: {}, requestDelete: {})
    }
}

#Preview("Present") {
    QRPresentView(code: QRCodesPreviewData.codes[0])
}
