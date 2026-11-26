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
    private let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        GridRow {
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

extension View {
    /// Sets a control apart from the caption above it, which describes a different control.
    func settingsButtonBelowCaption() -> some View {
        padding(.top, 6)
    }
}

/// Lets a short list fit its contents while keeping long lists within the pane.
struct SettingsItemList<Rows: View>: View {
    @ViewBuilder var rows: Rows
    @Environment(\.displayScale) private var displayScale
    @State private var metrics: ContentMetrics?

    private struct ContentMetrics: Equatable {
        let viewportHeight: CGFloat
        let firstBaseline: CGFloat?
    }

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: 8)
        let firstBaseline = metrics?.firstBaseline

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                rows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            // Measure in the padded content so scrolling doesn't move the form label.
            .backgroundPreferenceValue(FirstListTitleBaseline.self) { anchor in
                Color.clear.onGeometryChange(for: ContentMetrics.self) { geometry in
                    ContentMetrics(
                        viewportHeight: min(geometry.size.height, 220),
                        firstBaseline: anchor.map { geometry[$0].y }
                    )
                } action: { metrics = $0 }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: metrics?.viewportHeight)
        .background(.quinary)
        .clipShape(outline)
        .overlay {
            outline.strokeBorder(.separator, lineWidth: 1 / displayScale)
                .allowsHitTesting(false)
        }
        .alignmentGuide(.firstTextBaseline) { firstBaseline ?? $0[.firstTextBaseline] }
    }
}

private enum FirstListTitleBaseline: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? { nil }

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

extension Text {
    func settingsListItemTitle() -> some View {
        overlay(alignment: .leadingFirstTextBaseline) {
            Color.clear
                .frame(width: 0, height: 0)
                .anchorPreference(key: FirstListTitleBaseline.self, value: .topLeading) { $0 }
        }
    }
}
