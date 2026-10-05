import AppKit

/// An input device whose events can be delivered to or withheld from the virtual machine.
enum VMInputDevice: Hashable, CaseIterable, Sendable {
    case keyboard
    case pointingDevice
}

extension VMInputDevice {
    var deliveryMask: VMEventDeliveryMask {
        switch self {
        case .keyboard: .keyboard
        case .pointingDevice: .mouse
        }
    }

    /// The modifier keys that toggle delivery of this device's events when held down on their own.
    ///
    /// The shortcuts are made up of modifier keys only so that holding one down doesn't type anything in the guest.
    var toggleModifiers: NSEvent.ModifierFlags {
        switch self {
        case .keyboard: [.control, .option, .command]
        case .pointingDevice: [.control, .option, .shift]
        }
    }

    /// The symbols for the keys in ``toggleModifiers``, in the order they're conventionally displayed.
    var toggleShortcutSymbols: [String] {
        switch self {
        case .keyboard: ["⌃", "⌥", "⌘"]
        case .pointingDevice: ["⌃", "⌥", "⇧"]
        }
    }
}

extension NSEvent.ModifierFlags {
    /// The modifier keys that are taken into account when matching an input toggle shortcut.
    static let inputToggleCandidates: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
}
