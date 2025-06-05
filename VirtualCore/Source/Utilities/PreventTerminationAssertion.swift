import Cocoa
import BuddyKit
import os

/// An assertion that prevents the app from being terminated during its lifetime.
public final class PreventTerminationAssertion: NSObject {
    private let _isValid = OSAllocatedUnfairLock(initialState: true)
    public private(set) var isValid: Bool {
        get { _isValid.withLock { $0 } }
        set { _isValid.withLock { $0 = newValue } }
    }

    private let logger: Logger
    public let id: String
    public let reason: String
    let invalidationHandler: (PreventTerminationAssertion) -> ()

    fileprivate init(reason: String, invalidationHandler: @escaping (PreventTerminationAssertion) -> ()) {
        self.id = UUID().uuidString
        self.reason = reason
        self.invalidationHandler = invalidationHandler
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "PreventTerminationAssertion(\(reason.quoted))")

        super.init()
    }

    public func invalidate() {
        logger.debug(#function)

        assert(isValid, "Attempt to invalidate \(description) multiple times!")

        isValid = false

        invalidationHandler(self)
    }

    public override var description: String { "#\(id.shortID) (\(reason.quoted))" }

    deinit {
        if isValid {
            invalidate()
        }
    }
}

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "NSApplication+PreventTermination")

public extension NSApplication {

    var assertionsPreventingAppTermination: [PreventTerminationAssertion] {
        Self.preventTerminationAssertions.dictionaryRepresentation().values.filter(\.isValid)
    }

    var isTerminationBeingPreventedByAssertion: Bool { !assertionsPreventingAppTermination.isEmpty }

    /// Prevents the app from being terminated for the lifetime of the returned object, or until ``PreventTerminationAssertion/invalidate()`` is called on it.
    ///
    /// If multiple ``PreventTerminationAssertion`` objects are valid, the app will only terminate once all of them have been invalidated,
    /// and only if `.terminateLater` was returned from `applicationShouldTerminate`, implemented in the app delegate.
    func preventTermination(forReason reason: String) -> PreventTerminationAssertion {
        let assertion = PreventTerminationAssertion(reason: reason) { self.handleAssertionInvalidated($0) }

        Self.preventTerminationAssertions.setObject(assertion, forKey: assertion.id as NSString)

        logger.info("Activated prevent termination assertion: \(assertion, privacy: .public)")

        return assertion
    }
    
}

// MARK: - Assertion Management

private extension NSApplication {
    static let preventTerminationAssertions = NSMapTable<NSString, PreventTerminationAssertion>(keyOptions: [.strongMemory, .objectPersonality], valueOptions: [.weakMemory])

    func handleAssertionInvalidated(_ assertion: PreventTerminationAssertion) {
        Self.preventTerminationAssertions.removeObject(forKey: assertion.id as NSString)

        if !isTerminationBeingPreventedByAssertion {
            logger.info("All prevent termination assertions invalidated, allowing termination.")

            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}
