import AppKit

/// Monitors events sent to this app, to other apps, or both, managing the lifecycle of the underlying AppKit monitors.
@MainActor
final class ManagedEventMonitor {
    struct Scope: OptionSet, Hashable {
        let rawValue: Int

        /// Events sent to this app.
        static let local = Scope(rawValue: 1 << 0)
        /// Events sent to other apps.
        static let global = Scope(rawValue: 1 << 1)

        static let all: Scope = [.local, .global]
    }

    /// Receives a monitored event along with the scope it was observed in.
    /// For events in the ``Scope/local`` scope, returning `false` stops the event from being dispatched.
    /// The return value is ignored for events in the ``Scope/global`` scope, which can't be intercepted.
    typealias Handler = (_ event: NSEvent, _ scope: Scope) -> Bool

    let mask: NSEvent.EventTypeMask
    let scope: Scope

    private let handler: Handler

    init(mask: NSEvent.EventTypeMask, scope: Scope = .all, handler: @escaping Handler) {
        self.mask = mask
        self.scope = scope
        self.handler = handler
    }

    private var monitors = [Any]()

    var isActive: Bool { !monitors.isEmpty }

    func activate() {
        guard !isActive else { return }

        if scope.contains(.local) {
            let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else { return event }
                return handler(event, .local) ? event : nil
            }
            if let monitor { monitors.append(monitor) }
        }

        if scope.contains(.global) {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else { return }
                _ = handler(event, .global)
            }
            if let monitor { monitors.append(monitor) }
        }
    }

    func invalidate() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }
}
