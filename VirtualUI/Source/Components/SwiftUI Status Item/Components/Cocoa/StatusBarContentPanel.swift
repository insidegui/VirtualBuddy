import Cocoa

final class StatusBarContentPanel: NSPanel {

    override var canBecomeKey: Bool { true }

    @objc func hasKeyAppearance() -> Bool {
        return true
    }

    @objc func hasMainAppearance() -> Bool {
        return true
    }

}
