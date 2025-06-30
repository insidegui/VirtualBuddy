import SwiftUI
import BuddyKit

struct FirstLaunchExperienceView: View {
    var action: () -> ()

    @State private var buttonRevealed = false

    var body: some View {
        ZStack {
            AnimationView()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()

                if buttonRevealed {
                    Button {
                        action()
                    } label: {
                        Text("Create Virtual Machine")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(FirstLaunchButtonStyle())
                    .controlSize(.large)
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .task {
            withAnimation(.snappy.delay(7.5)) {
                buttonRevealed = true
            }
        }
    }

    private struct AnimationView: NSViewRepresentable {
        typealias NSViewType = FirstLaunchExperienceNSView

        func makeNSView(context: Context) -> FirstLaunchExperienceNSView {
            FirstLaunchExperienceNSView(frame: .zero)
        }

        func updateNSView(_ nsView: FirstLaunchExperienceNSView, context: Context) {

        }

        final class FirstLaunchExperienceNSView: NSView {
            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)

                setup()
            }

            required init?(coder: NSCoder) {
                fatalError()
            }

            private lazy var assetLayer = CALayer.load(assetNamed: "FirstLaunchExperience", bundle: .virtualUI) ?? CALayer()

            #if DEBUG
            private var debugSkipAnimation: Bool { false }
            #endif

            private func setup() {
                platformLayer.addSublayer(assetLayer)
                assetLayer.isGeometryFlipped = false

                assetLayer.beginTime = CACurrentMediaTime()
                assetLayer.speed = 1

                #if DEBUG
                if debugSkipAnimation {
                    assetLayer.timeOffset = 10
                }
                #endif
            }

            override var isFlipped: Bool { true }

            override func layout() {
                super.layout()

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                defer { CATransaction.commit() }

                assetLayer.frame = bounds
                assetLayer.sublayer(named: "background")?.frame = bounds
                assetLayer.sublayer(path: "background.fullBleed")?.frame = bounds
                assetLayer.sublayer(path: "background.brighten")?.frame = bounds
                assetLayer.sublayer(named: "backdrop")?.frame = bounds
                assetLayer.sublayer(named: "iconTransform")?.position = CGPoint(x: bounds.midX, y: bounds.midY)
                assetLayer.sublayer(named: "spotlightBleed")?.frame = bounds
                assetLayer.sublayer(named: "scanlines")?.frame.size.width = bounds.width
                if let backdropMask = assetLayer.sublayer(named: "backdrop")?.mask {
                    backdropMask.bounds.size = bounds.size
                    backdropMask.position = CGPoint(x: bounds.midX, y: bounds.maxY)
                }
            }
        }

    }
}

private struct FirstLaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Material.regular, in: shape)
            .overlay {
                ZStack {
                    Color.accentColor
                        .blendMode(.color)
                        .opacity(configuration.isPressed ? 1 : 0.7)

                    shape
                        .inset(by: 10)
                        .fill(Color.accentColor)
                        .blur(radius: 10)
                        .blendMode(.plusLighter)
                        .opacity(configuration.isPressed ? 0.1 : 0)

                    LinearGradient(colors: [.accentColor.opacity(0.9), .accentColor.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                        .mask {
                            shape.strokeBorder(Color.white, lineWidth: 1)
                        }
                        .blendMode(.plusLighter)
                        .opacity(0.3)
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(configuration.isPressed ? .linear(duration: 0) : .snappy, value: configuration.isPressed)
    }

    var shape: some InsettableShape {
        Capsule(style: .continuous)
    }
}

#if DEBUG
#Preview {
    FirstLaunchExperienceView() { }
        .frame(width: 900, height: 600)
}
#endif
