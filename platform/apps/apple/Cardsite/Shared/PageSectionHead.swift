import SwiftUI
import StudioKit

/// The head of a section within a page: a kicker with the accent dot, a
/// two-tone title, and an optional trailing action. The web dashboard's
/// `SecHead`; the section-level partner of `StudioPageHead`.
///
///     PageSectionHead(kicker: "Create", title: "Start something ", accent: "new.")
struct PageSectionHead<Trailing: View>: View {
    let kicker: String
    let title: String
    var accent: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: StudioSpace.s4) {
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                StudioKicker(kicker)
                if accent.isEmpty {
                    Text(title)
                        .studioText(.title)
                        .foregroundStyle(Color.studioText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StudioTwoToneTitle(title, accent: accent, style: .title)
                        .foregroundStyle(Color.studioText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: StudioSpace.s4)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageSectionHead where Trailing == EmptyView {
    init(kicker: String, title: String, accent: String = "") {
        self.init(kicker: kicker, title: title, accent: accent) { EmptyView() }
    }
}

#Preview("Section heads") {
    VStack(alignment: .leading, spacing: StudioSpace.s8) {
        PageSectionHead(kicker: "Create", title: "Start something ", accent: "new.")
        PageSectionHead(kicker: "Statistics · Last 30 days", title: "All your ", accent: "resources.") {
            Button("All analytics") {}
        }
    }
    .padding(StudioSpace.s6)
    .background(Color.studioBg)
}
