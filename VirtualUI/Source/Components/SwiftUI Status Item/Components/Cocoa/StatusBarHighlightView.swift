import Cocoa
import SwiftUI

struct StatusBarHighlightView: NSViewRepresentable {

    typealias NSViewType = NSView

    var isHighlighted: Bool

    func makeNSView(context: Context) -> NSViewType {
        let v = NSView()

        updateHighlight(in: v)

        return v
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        updateHighlight(in: nsView)
    }

    private func updateHighlight(in view: NSViewType) {
        NSStatusItem.vui_drawMenuBarHighlight(
            in: view,
            highlighted: isHighlighted,
            inset: StatusItemButtonStyle.highlightCornerRadius * 0.5
        )
    }

}

#if DEBUG

struct StatusBarHighlightView_Previews: PreviewProvider {
    static var previews: some View {
        StatusBarHighlightView(isHighlighted: true)
            .frame(width: 30, height: 30)
            .previewDisplayName("Highlighted")
        StatusBarHighlightView(isHighlighted: false)
            .frame(width: 30, height: 30)
            .previewDisplayName("Normal")
    }
}

#endif
