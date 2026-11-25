import AppKit
import OSLog

/// Base class for app-wide states that remain in effect for as long as at least one assertion requesting them is valid.
///
/// An assertion is valid from the moment it's created until ``invalidate()`` is called or the object is released, whichever happens first.
/// The corresponding state is entered when the first assertion of a given type is created and exited when the last one is invalidated.
@MainActor
public class AppAssertion {
    private static let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: AppAssertion.self))

    /// Number of valid assertions for each assertion type.
    private static var counts = [ObjectIdentifier: Int]()

    private var isValid = true

    fileprivate init() {
        let key = ObjectIdentifier(Self.self)
        let count = Self.counts[key, default: 0] + 1
        Self.counts[key] = count

        guard count == 1 else { return }

        Self.logger.debug("Activating \(String(describing: Self.self), privacy: .public)")

        Self.activate()
    }

    /// Ends this assertion. Does nothing if the assertion has already been invalidated.
    public final func invalidate() {
        guard isValid else { return }
        isValid = false

        Self.release()
    }

    private static func release() {
        let key = ObjectIdentifier(self)

        guard let count = counts[key], count > 0 else {
            assertionFailure("Unbalanced release of \(self)")
            return
        }

        counts[key] = count - 1

        guard count == 1 else { return }

        logger.debug("Deactivating \(String(describing: self), privacy: .public)")

        deactivate()
    }

    /// Called when the first assertion of this type is created.
    fileprivate class func activate() { }

    /// Called when the last assertion of this type is invalidated.
    fileprivate class func deactivate() { }

    deinit {
        guard isValid else { return }

        let type = Self.self

        Task { @MainActor in type.release() }
    }
}

// MARK: - Activation Policy

/// Keeps the app running with the regular activation policy, which gives it a Dock icon and a main menu.
///
/// Meant for apps that normally run as accessories, such as menu bar apps, but have windows
/// that should behave like regular app windows while they're open.
public final class AppActivationPolicyAssertion: AppAssertion {
    fileprivate override class func activate() {
        NSApp.setActivationPolicy(.regular)

        /// The main menu only shows up after the app is activated with the new policy in effect.
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    fileprivate override class func deactivate() {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Menu Bar Visibility

/// Keeps the menu bar visible, even in spaces where it's normally hidden, such as full screen spaces.
///
/// - note: This is not needed in macOS 27 and later for status items that use an expanded interface session.
public final class MenuBarVisibilityAssertion: AppAssertion {
    fileprivate override class func activate() {
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.beginMenuTrackingNotification"), object: nil)
    }

    fileprivate override class func deactivate() {
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.endMenuTrackingNotification"), object: nil)
    }
}

@MainActor
public extension NSApplication {
    /// Switches the app to the regular activation policy until the returned assertion is invalidated or released.
    func requestRegularActivationPolicy() -> AppActivationPolicyAssertion { AppActivationPolicyAssertion() }

    /// Keeps the menu bar visible until the returned assertion is invalidated or released.
    func requestMenuBarVisible() -> MenuBarVisibilityAssertion { MenuBarVisibilityAssertion() }
}
