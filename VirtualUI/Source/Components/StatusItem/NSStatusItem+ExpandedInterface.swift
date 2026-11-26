import AppKit

extension NSStatusItem {
    /// Asks the system to begin an expanded interface session for the status item, as if the user had clicked it.
    /// - Returns: `true` if the request was sent, `false` if there's no way to request a session in the current system.
    func vui_requestExpandedInterfaceSession() -> Bool {
        ExpandedInterfaceSessionRequest.send(to: self)
    }

    /// AppKit only begins expanded interface sessions in response to user interaction with the status item,
    /// there's currently no public API for an app to begin one programmatically (FB23688090).
    /// See https://github.com/feedback-assistant/reports/issues/821
    private enum ExpandedInterfaceSessionRequest {
        static let publicSelector = NSSelectorFromString("requestExpandedInterfaceSession")
        static let privateSelector = NSSelectorFromString("_requestExpandedInterfaceSession")

        /// Prefers the public spelling so that this automatically adopts the API in case it becomes available.
        static let selector: Selector? = [publicSelector, privateSelector].first(where: { NSStatusItem.instancesRespond(to: $0) })

        static func send(to statusItem: NSStatusItem) -> Bool {
            guard #available(macOS 27, *), let selector else { return false }

            return NSApp.sendAction(selector, to: statusItem, from: nil)
        }
    }
}
