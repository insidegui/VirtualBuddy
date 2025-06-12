import SwiftUI
import VirtualCore
import BuddyKit

enum VirtualBuddyMonoStyle: Hashable {
    case `default`
    case success
    case failure
}

struct VirtualBuddyMonoProgressView: View {
    var progress: Double?
    var status: Text
    var style: VirtualBuddyMonoStyle = .default

    var spacing: Double { 16 }

    private var foregroundColor: Color {
        switch style {
        case .default: .white
        case .success: .green
        case .failure: .red
        }
    }

    var body: some View {
        VStack {
            Spacer()

            VirtualBuddyMonoIcon(style: style)

            Spacer()

            VStack(spacing: spacing) {
                RamRodProgressView(progress: progress ?? 0)
                    .opacity(style == .default && progress != nil ? 1 : 0)

                status
                    .font(.subheadline)
            }
            .padding(.bottom, spacing)
        }
        .monospacedDigit()
        .frame(width: 240)
        .multilineTextAlignment(.center)
        .foregroundStyle(foregroundColor)
        .tint(foregroundColor)
    }
}

private struct RamRodProgressView: View {
    var progress: Double

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.16))

            ProgressBarShapeView(progress: progress)
        }
            .clipShape(shape)
            .overlay(shape.stroke(Color(white: 0.25), lineWidth: 1))
            .frame(height: 6)
    }

    private var shape: some InsettableShape {
        Capsule(style: .continuous)
    }
}

/**
 You see, animating a white rectangle growing in width is a very expensive operation that SwiftUI
 is completely unable to do by itself without consuming an unhealthy amount of CPU,
 so this uses Core Animation instead to offload that expensive computation to the WindowServer/GPU.
 */
private struct ProgressBarShapeView: NSViewRepresentable {
    typealias NSViewType = _Representable

    var progress: Double = 0

    func makeNSView(context: Context) -> _Representable {
        _Representable(frame: .zero)
    }

    func updateNSView(_ nsView: _Representable, context: Context) {
        nsView.progress = progress
    }

    final class _Representable: NSView {
        private lazy var bar = CALayer()

        @Invalidating(.layout)
        var progress: Double = 0

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            platformLayer.addSublayer(bar)
            bar.backgroundColor = .white
            bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        override func layout() {
            super.layout()

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            bar.position = CGPoint(x: bounds.minX, y: bounds.midY)
            bar.frame.size.height = bounds.height

            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(.init(name: .linear))
            bar.frame.size.width = bounds.width * progress
            CATransaction.commit()
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .download)
}
#endif // DEBUG
