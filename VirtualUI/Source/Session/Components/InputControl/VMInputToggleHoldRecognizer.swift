import AppKit

/// Describes the progress of the user holding down the shortcut that toggles an input device.
enum VMInputToggleHoldEvent: Equatable {
    /// The shortcut has been held down for long enough that it's likely intentional.
    /// The toggle takes effect if it's held down for the remaining time.
    case began(VMInputDevice, remaining: TimeInterval)
    /// The shortcut was let go of or interrupted after ``began(_:remaining:)`` and before the toggle took effect.
    case cancelled
    /// The shortcut was held down for the required time, so the input device should be toggled.
    case completed(VMInputDevice)
}

/// Recognizes when the modifier keys that toggle an input device are held down on their own for long enough.
///
/// Requiring the keys to be held down makes it unlikely that the shortcut gets in the way of
/// a key combination that's being used in the guest operating system.
@MainActor
final class VMInputToggleHoldRecognizer {
    /// How long the shortcut must be held down for before the toggle takes effect.
    static let holdDuration: TimeInterval = 2

    /// How long the shortcut must be held down for before the hold is reported,
    /// so that key combinations pressed in passing go unnoticed.
    static let coachingDelay: TimeInterval = 0.4

    var handler: ((VMInputToggleHoldEvent) -> Void)?

    /// The device matching the modifier keys that are currently down.
    /// Kept after the hold ends so that a new one only starts once the modifier keys change.
    private var heldDevice: VMInputDevice?
    private var holdTask: Task<Void, Never>?
    private var hasBegun = false

    func modifiersChanged(to modifiers: NSEvent.ModifierFlags) {
        let pressed = modifiers.intersection(.inputToggleCandidates)
        let device = VMInputDevice.allCases.first { $0.toggleModifiers == pressed }

        guard device != heldDevice else { return }

        interrupt()

        heldDevice = device

        guard let device else { return }

        holdTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.coachingDelay))
                try Task.checkCancellation()

                let remaining = Self.holdDuration - Self.coachingDelay
                self?.begin(device, remaining: remaining)

                try await Task.sleep(for: .seconds(remaining))
                try Task.checkCancellation()

                self?.complete(device)
            } catch {
                /// Cancellation is reported by whoever cancelled the task.
            }
        }
    }

    /// Ends the current hold because something other than the shortcut's modifier keys was pressed.
    /// A new hold can only start after the modifier keys change.
    func interrupt() {
        holdTask?.cancel()
        holdTask = nil

        guard hasBegun else { return }

        hasBegun = false
        handler?(.cancelled)
    }

    /// Ends the current hold and forgets about the modifier keys that are down.
    func reset() {
        interrupt()
        heldDevice = nil
    }

    private func begin(_ device: VMInputDevice, remaining: TimeInterval) {
        hasBegun = true
        handler?(.began(device, remaining: remaining))
    }

    private func complete(_ device: VMInputDevice) {
        hasBegun = false
        holdTask = nil
        handler?(.completed(device))
    }
}
