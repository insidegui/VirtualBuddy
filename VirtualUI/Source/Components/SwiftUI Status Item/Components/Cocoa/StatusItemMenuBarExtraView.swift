import Cocoa

final class StatusItemMenuBarExtraView: NSView {

    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()

        guard let superview else { return }

        wantsLayer = true
        layer?.masksToBounds = false

        superview.wantsLayer = true
        superview.layer?.masksToBounds = false

        superview.superview?.layer?.masksToBounds = false
    }

}
