import SwiftUI

/// The contents of the HUD that tells the user about the state of an input device.
struct VMInputStatusHUD: Equatable {
    enum Phase: Equatable {
        /// The shortcut that toggles the device is being held down,
        /// the toggle takes effect if it's held down for the remaining time.
        case holding(remaining: TimeInterval)
        /// The device has just been connected to or disconnected from the virtual machine.
        case changed
    }

    var device: VMInputDevice
    /// Whether the device's events are currently being delivered to the virtual machine.
    var isConnected: Bool
    var phase: Phase
}

/// Decides when the input status HUD is on screen and what it shows.
@MainActor
@Observable
final class VMInputStatusHUDPresenter {
    /// How long the HUD stays on screen after an input device is connected or disconnected.
    static let displayDuration: TimeInterval = 2.5

    private(set) var hud: VMInputStatusHUD?

    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    func holdBegan(for device: VMInputDevice, isConnected: Bool, remaining: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = nil

        hud = VMInputStatusHUD(device: device, isConnected: isConnected, phase: .holding(remaining: remaining))
    }

    func holdCancelled() {
        guard case .holding = hud?.phase else { return }

        hud = nil
    }

    func statusChanged(for device: VMInputDevice, isConnected: Bool) {
        hud = VMInputStatusHUD(device: device, isConnected: isConnected, phase: .changed)

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.displayDuration))

            guard !Task.isCancelled else { return }

            self?.hud = nil
        }
    }
}
