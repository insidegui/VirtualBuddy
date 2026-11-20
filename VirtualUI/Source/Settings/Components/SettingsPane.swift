import SwiftUI

struct SettingsPane<Rows: View>: View {
    @ViewBuilder var rows: Rows

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 12) {
            rows
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsRow<Content: View>: View {
    private let label: LocalizedStringKey
    private let alignment: VerticalAlignment
    private let content: Content

    init(_ label: LocalizedStringKey, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        GridRow(alignment: alignment) {
            Text(label, bundle: #bundle)
                .multilineTextAlignment(.trailing)
                .gridColumnAlignment(.trailing)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .gridCellUnsizedAxes(.horizontal)
            .padding(.vertical, 8)
    }
}

struct SettingsCaption: View {
    private let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text, bundle: #bundle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Lets a short list fit its contents while keeping long lists within the pane.
struct SettingsItemList<Rows: View>: View {
    @ViewBuilder var rows: Rows
    @State private var viewportHeight: CGFloat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                rows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
            .onGeometryChange(for: CGFloat.self, of: { min($0.size.height, 220) }) {
                viewportHeight = $0
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: viewportHeight)
    }
}
