import SwiftUI
import BuddyPlatform

extension View {
    func virtualBuddyBottomBar<Content>(hidden: Bool = false, @ViewBuilder content: () -> Content) -> some View where Content : View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if !hidden {
                content().virtualBuddyBottomBarStyle()
            }
        }
        .compositingGroup()
    }
}

private extension View {
    @ViewBuilder
    func virtualBuddyBottomBarStyle() -> some View {
        modifier(VirtualBuddyBottomBarModifier())
    }
}

private struct VirtualBuddyBottomBarModifier: ViewModifier {
    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

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
                            VariableBlur()
                        }
                        .background {
                            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).blendMode(.destinationOut)
                        }
                } else {
                    view
                        .background(Material.bar)
                        .overlay(alignment: .top) { Divider() }
                }
            }
    }

    private struct VariableBlur: NSViewRepresentable {
        typealias NSViewType = _LayerView

        func makeNSView(context: Context) -> _LayerView {
            _LayerView()
        }

        func updateNSView(_ nsView: _LayerView, context: Context) {

        }

        final class _LayerView: NSView, CALayerDelegate {
            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)

                setup()
            }

            required init?(coder: NSCoder) {
                fatalError()
            }

            private lazy var assetLayer = CALayer.load(assetNamed: "BottomBarVariableBlur", bundle: .virtualUI) ?? CALayer()
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
}
