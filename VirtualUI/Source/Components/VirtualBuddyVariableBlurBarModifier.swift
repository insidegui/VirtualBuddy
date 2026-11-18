import SwiftUI
import BuddyPlatform

extension View {
    func virtualBuddyVariableBlurBar<Content>(edge: VerticalEdge, hidden: Bool = false, @ViewBuilder content: () -> Content) -> some View where Content : View {
        safeAreaInset(edge: edge, spacing: 0) {
            if !hidden {
                content().virtualBuddyVariableBlurBarStyle(edge: edge)
            }
        }
        .compositingGroup()
    }
}

private extension View {
    @ViewBuilder
    func virtualBuddyVariableBlurBarStyle(edge: VerticalEdge) -> some View {
        modifier(VirtualBuddyVariableBlurBarModifier(edge: edge))
    }
}

private struct VirtualBuddyVariableBlurBarModifier: ViewModifier {
    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

    var edge: VerticalEdge

    func body(content: Content) -> some View {
        content
            .airGlassButtonStyle()
            .frame(maxWidth: .infinity)
            .controlSize(.extraLarge)
            .padding()
            .modifier { view in
                if isLiquidGlassSupported {
                    view
                        .background {
                            _VirtualBuddyVariableBlur(edge: edge)
                        }
                        .background {
                            _VirtualBuddyBarGradient(edge: edge)
                                .blendMode(.destinationOut)
                        }
                } else {
                    view
                        .background(Material.bar)
                        .overlay(alignment: .top) { Divider() }
                }
            }
    }
}

struct _VirtualBuddyBarGradient: View {
    var edge: VerticalEdge

    private var gradientPoints: (start: UnitPoint, end: UnitPoint) {
        switch edge {
        case .top:
            (.bottom, .top)
        case .bottom:
            (.top, .bottom)
        }
    }

    var body: some View {
        LinearGradient(colors: [.white.opacity(0), .white], startPoint: gradientPoints.start, endPoint: gradientPoints.end)
    }
}

struct _VirtualBuddyVariableBlur: NSViewRepresentable {
    typealias NSViewType = _LayerView

    let edge: VerticalEdge

    func makeNSView(context: Context) -> _LayerView {
        _LayerView(edge: edge)
    }

    func updateNSView(_ nsView: _LayerView, context: Context) {

    }

    final class _LayerView: NSView, CALayerDelegate {
        let edge: VerticalEdge

        init(edge: VerticalEdge) {
            self.edge = edge

            super.init(frame: .zero)

            setup()
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private var assetName: String {
            switch edge {
            case .top: "TopBarVariableBlur"
            case .bottom: "BottomBarVariableBlur"
            }
        }

        private lazy var assetLayer = CALayer.load(assetNamed: assetName, bundle: .virtualUI) ?? CALayer()
        private lazy var backdrop = assetLayer.sublayer(named: "backdrop") ?? CALayer()

        func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
            NSNull()
        }

        private func setup() {
            platformLayer.addSublayer(assetLayer)
            platformLayer.delegate = self
            assetLayer.delegate = self
            backdrop.delegate = self

            setValue(false, forKeyPath: "allowsGroupBlending")
        }

        override func layout() {
            super.layout()

            assetLayer.frame = platformLayer.bounds
            backdrop.frame = assetLayer.bounds
        }
    }
}
