import SwiftUI

struct ContinuousProgressIndicator<Content: View>: View {
    var duration: TimeInterval
    @ViewBuilder var content: (Double) -> Content

    @State private var progress = Double(0)

    var body: some View {
        ZStack {
            content(progress)
        }
        .task { @MainActor in
            withAnimation(.easeIn(duration: duration)) {
                progress = 1
            }
        }
    }
}
