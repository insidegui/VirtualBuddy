import SwiftUI

struct VerticalLabeledContentStyle: LabeledContentStyle {
    static let defaultSpacing: Double = 6

    var spacing: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .listRowSeparatorLeading, spacing: spacing ?? Self.defaultSpacing) {
            configuration.label

            configuration.content
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

extension LabeledContentStyle where Self == VerticalLabeledContentStyle {
    static var vertical: VerticalLabeledContentStyle { VerticalLabeledContentStyle() }
    static func vertical(spacing: Double) -> VerticalLabeledContentStyle { VerticalLabeledContentStyle(spacing: spacing) }
}
