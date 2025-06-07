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
            Rectangle()
                .fill(Color(white: 0.16))
            GeometryReader { proxy in
                Color(white: 0.82)
                    .frame(width: proxy.size.width * (progress / 1.0), alignment: .leading)
            }
        }
            .clipShape(shape)
            .overlay(shape.stroke(Color(white: 0.25), lineWidth: 1))
            .frame(height: 6)
    }

    private var shape: some InsettableShape {
        Capsule(style: .continuous)
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .download)
}
#endif // DEBUG
