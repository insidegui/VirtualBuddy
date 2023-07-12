import SwiftUI

struct StatusBarPanelChromeMetrics {
    static var shadowPadding: CGFloat { 26 }
    static var cornerRadius: CGFloat { 15 }
    static var innerStrokeWidth: CGFloat { 1 }
    static var innerStrokeInset: CGFloat { innerStrokeWidth * 0.5 }
    static var outerStrokeWidth: CGFloat { .onePixel }
}

struct StatusBarPanelChrome<Content: View, S: InsettableShape>: View {
    var contentBuilder: () -> Content
    var shape: S

    var body: some View {
        contentBuilder()
            .background(chromeBackground)
    }

    @ViewBuilder
    private var chromeBackground: some View {
        MaterialView()
            .materialType(.hudWindow)
            .materialBlendingMode(.behindWindowForPreviews)
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.7), radius: 1, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.28), radius: 13, x: 0, y: 0)
            .compositingGroup()
            .overlay(innerStroke)
            .overlay(outerStroke)
    }

    @Environment(\.colorScheme)
    private var colorScheme

    private var outerStrokeWidth: CGFloat { 0.5 }

    private var innerStroke: some View {
        shape
            .inset(by: StatusBarPanelChromeMetrics.innerStrokeInset)
            .stroke(Color.statusItemPanelChromeBorder.opacity(0.7), lineWidth: StatusBarPanelChromeMetrics.innerStrokeWidth)
            .blendMode(.plusLighter)
            .opacity(colorScheme == .dark ? 1 : 0)
            .zIndex(9999)
    }

    private var outerStroke: some View {
        shape
            .inset(by: -outerStrokeWidth * 0.5)
            .stroke(Color.black, lineWidth: outerStrokeWidth)
            .opacity(colorScheme == .dark ? 1 : 0)
    }

}

extension StatusBarPanelChrome where S == RoundedRectangle {

    init(contentBuilder: @escaping () -> Content) {
        self.init(contentBuilder: contentBuilder, shape: RoundedRectangle(cornerRadius: StatusBarPanelChromeMetrics.cornerRadius, style: .continuous))
    }

}

extension Color {

    static let statusItemPanelChromeBorder = Color("StatusItemPanelChromeBorder", bundle: .virtualUIFoundation)

}

#if DEBUG
struct StatusBarPanelChrome_Previews: PreviewProvider {
    static var previews: some View {
        StatusBarPanelChrome {
            Text("Hello, World!")
                .frame(width: 300, height: 300)
        }
        .padding(100)
        .previewDisplayName("Light")

        StatusBarPanelChrome {
            Text("Hello, World!")
                .frame(width: 300, height: 300)
        }
        .padding(100)
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")
    }
}
#endif
