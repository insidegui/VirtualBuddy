import SwiftUI
import BuddyKit

/// A view that simulates a display chrome, currently used during installation.
struct VirtualDisplayView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var viewModel: VMInstallationViewModel

    static var cornerRadius: CGFloat { 12 }

    var body: some View {
        ZStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color(white: 0.03))
        .overlay {
            LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .init(x: 0.2, y: 0), endPoint: .init(x: 0.3, y: 1.2))
                .blendMode(.plusLighter)
                .opacity(0.1)
        }
        .clipShape(shape)
        .chromeBorder(shape: shape, highlightEnabled: false)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .download)
}
#endif
