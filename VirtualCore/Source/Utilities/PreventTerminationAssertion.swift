import Cocoa
import BuddyKit
import OSLog

/// An assertion that prevents the app from being terminated during its lifetime.
public final class PreventTerminationAssertion: NSObject {
    public typealias ShouldTerminateHandler = @MainActor (PreventTerminationAssertion) -> NSApplication.TerminateReply
    public typealias InvalidationHandler = (PreventTerminationAssertion) -> ()

    @Lock public private(set) var isValid: Bool = true

    private let logger: Logger

    public let id: String
    public let reason: String
    private let shouldTerminateHandler: ShouldTerminateHandler?
    private let invalidationHandler: InvalidationHandler?

    fileprivate init(id: String = UUID().uuidString,
                     reason: String,
                     shouldTerminate: ShouldTerminateHandler? = nil,
                     invalidationHandler: InvalidationHandler? = nil)
    {
        self.id = id
        self.reason = reason
        self.shouldTerminateHandler = shouldTerminate
        self.invalidationHandler = invalidationHandler
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "PreventTerminationAssertion(\(reason.quoted))")

        super.init()
    }

    @MainActor
    public func handleShouldTerminate() -> NSApplication.TerminateReply? {
        guard let shouldTerminateHandler else { return nil }
        return shouldTerminateHandler(self)
    }

    public func invalidate() {
        logger.debug(#function)

        assert(isValid, "Attempt to invalidate \(description) multiple times!")

        isValid = false

        invalidationHandler?(self)
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
    /// - Parameters:
    ///   - id: An arbitrary identifier. Uses a random UUID by default.
    ///   - reason: A user-facing string describing the reason why app termination is being prevented. This is used in the default UI alert if a custom `shouldTerminate` block is not provided.
    ///   - shouldTerminate: A closure that can be used to present a custom confirmation alert and return the appropriate response for the app termination request.
    ///   - invalidationHandler: A closure that's called when the assertion gets invalidated.
    /// - Returns: The assertion preventing app termination. Callers **must** retain a reference to this object until you want to invalidate the assertion.
    ///
    /// If multiple ``PreventTerminationAssertion`` objects are valid, the app will only terminate once all of them have been invalidated,
    /// and only if `.terminateLater` was returned from `applicationShouldTerminate`, implemented in the app delegate.
    func preventTermination(id: String = UUID().uuidString,
                            reason: String,
                            shouldTerminate: PreventTerminationAssertion.ShouldTerminateHandler? = nil,
                            invalidationHandler: PreventTerminationAssertion.InvalidationHandler? = nil) -> PreventTerminationAssertion
    {
        let assertion = PreventTerminationAssertion(id: id, reason: reason, shouldTerminate: shouldTerminate) { assertion in
            invalidationHandler?(assertion)
            self.handleAssertionInvalidated(assertion)
        }
        
        Self.preventTerminationAssertions.setObject(assertion, forKey: assertion.id as NSString)
        
        logger.info("Activated prevent termination assertion: \(assertion, privacy: .public)")
        
        return assertion
    }

    /// Instructs the app to terminate as soon as the last ``PreventTerminationAssertion`` gets invalidated.
    @MainActor
    var shouldTerminateWhenLastAssertionInvalidated: Bool {
        get { Self.shouldTerminateWhenLastAssertionInvalidated }
        set { Self.shouldTerminateWhenLastAssertionInvalidated = newValue }
    }

}

// MARK: - Assertion Management

private extension NSApplication {
    /// How long after the last assertion gets invalidated before the app will terminate automatically.
    /// If a new assertion is created before this time delay, then termination will wait until that new assertion gets invalidated before terminating.
    static let delayInSecondsBeforeAutomaticTermination: TimeInterval = 1

    static let preventTerminationAssertions = NSMapTable<NSString, PreventTerminationAssertion>(keyOptions: [.strongMemory, .objectPersonality], valueOptions: [.weakMemory])

    @Lock static var shouldTerminateWhenLastAssertionInvalidated = false

    func handleAssertionInvalidated(_ assertion: PreventTerminationAssertion) {
        Self.preventTerminationAssertions.removeObject(forKey: assertion.id as NSString)

        guard !isTerminationBeingPreventedByAssertion else { return }

        logger.info("All prevent termination assertions invalidated")

        guard shouldTerminateWhenLastAssertionInvalidated else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayInSecondsBeforeAutomaticTermination) { [self] in
            guard !isTerminationBeingPreventedByAssertion else {
                logger.info("New assertion prevents scheduled termination, waiting for it before terminating.")
                return
            }

            logger.info("Termination requested when all assertions invalidated, terminating now.")

            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}

// MARK: - Convenience

extension NSApplication.TerminateReply: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .terminateCancel: "cancel"
        case .terminateNow: "now"
        case .terminateLater: "later"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
