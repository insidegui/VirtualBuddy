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
                    .modifier {
                        if #available(macOS 26.0, *) {
                            $0
                                .buttonStyle(.glass)
                                .controlSize(.extraLarge)
                        } else {
                            $0.controlSize(.large)
                        }
                    }
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

            private func setup() {
                platformLayer.addSublayer(assetLayer)
                assetLayer.isGeometryFlipped = false

                assetLayer.beginTime = CACurrentMediaTime()
                assetLayer.speed = 1
            }

            override var isFlipped: Bool { true }

            override func layout() {
                super.layout()

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                defer { CATransaction.commit() }

                assetLayer.frame = bounds
                assetLayer.sublayer(named: "fullBleed")?.frame = bounds
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

#if DEBUG
#Preview {
    FirstLaunchExperienceView() { }
        .frame(width: 900, height: 600)
}
#endif
