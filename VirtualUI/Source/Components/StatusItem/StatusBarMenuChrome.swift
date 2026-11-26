import SwiftUI

/// Metrics for the chrome that ``StatusBarMenuWindowController`` draws around its content.
public enum StatusBarMenuChromeMetrics {
    /// Corner radius of the panel, which can be used by the panel's content in order to derive concentric shapes.
    public static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { 26 } else { 15 }
    }

    /// Transparent area around the panel that leaves room for its shadow.
    static var shadowPadding: CGFloat {
        if #available(macOS 26, *) { 64 } else { 26 }
    }
}

/// Draws the background, border and shadow for content presented in a ``StatusBarMenuWindowController``.
///
/// The window itself is fully transparent, so its appearance is entirely defined by this modifier,
/// which uses Liquid Glass when available and falls back to a traditional material in earlier systems.
struct StatusBarMenuChrome: ViewModifier {
    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

    func body(content: Content) -> some View {
        content
            .containerShape(shape)
            .clipShape(shape)
            .modifier {
                if #available(macOS 26, *), isLiquidGlassSupported {
                    $0.glassEffect(.regular, in: shape)
                } else {
                    $0.background { StatusBarMenuLegacyBackground(shape: shape) }
                }
            }
            .padding(StatusBarMenuChromeMetrics.shadowPadding)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StatusBarMenuChromeMetrics.cornerRadius, style: .continuous)
    }
}

/// Panel background for systems that don't support Liquid Glass.
private struct StatusBarMenuLegacyBackground: View {
    var shape: RoundedRectangle

    @Environment(\.colorScheme)
    private var colorScheme

    private let innerStrokeWidth: CGFloat = 1
    private let outerStrokeWidth: CGFloat = 0.5

    var body: some View {
        MaterialView()
            .materialType(.hudWindow)
            .materialBlendingMode(.behindWindowForPreviews)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.7), radius: 1)
            .shadow(color: .black.opacity(0.28), radius: 13)
            .compositingGroup()
            .overlay {
                if colorScheme == .dark {
                    shape
                        .inset(by: innerStrokeWidth * 0.5)
                        .stroke(Color.statusItemPanelChromeBorder.opacity(0.7), lineWidth: innerStrokeWidth)
                        .blendMode(.plusLighter)

                    shape
                        .inset(by: -outerStrokeWidth * 0.5)
                        .stroke(.black, lineWidth: outerStrokeWidth)
                }
            }
    }
}

#if DEBUG
#Preview("Status Bar Menu Chrome") {
    Text("Hello, World!")
        .frame(width: 300, height: 300)
        .modifier(StatusBarMenuChrome())
}
#endif
