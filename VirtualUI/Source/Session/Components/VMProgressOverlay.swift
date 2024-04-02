import SwiftUI

struct VMProgressOverlay: View {
    let message: String
    let duration: TimeInterval
    
    var body: some View {
        ContinuousProgressIndicator(duration: duration) { progress in
            MaskProgressView(progress: progress * 1.2, background: .tertiary, foreground: .primary) { _ in
                Text(message)
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            .scaleEffect(0.85 + 0.15 * progress)
        }
        .id(message)
        .transition(.scale(scale: 0.2).combined(with: .opacity))
    }
}
