import Foundation
import Virtualization

extension VBDisplayDevice {
    func validatedLiveDisplay(replacing current: VBDisplayDevice, guestType: VBGuestType) throws -> VBDisplayDevice {
        guard id == current.id else { throw Failure("A live display's identity can't be changed.") }
        if self == current { return current }
        guard Self.displayWidthRange.contains(width), Self.displayHeightRange.contains(height),
              !guestType.supportsDisplayPPI || Self.displayPPIRange.contains(pixelsPerInch) else {
            throw Failure("The requested display dimensions or pixel density are outside the supported range.")
        }
        var updated = self
        updated.name = current.name
        if !guestType.supportsDisplayPPI { updated.pixelsPerInch = current.pixelsPerInch }
        return updated
    }

    @available(macOS 14.0, *)
    func runtimeDisplayConfiguration(for guestType: VBGuestType) -> VZGraphicsDisplayConfiguration {
        switch guestType {
        case .mac: vzDisplay
        case .linux: vzScanout
        }
    }
}

extension VBMacConfiguration {
    /// A saved display preference may change geometry, but cannot add, remove, or reorder displays.
    func restoringLiveDisplays(_ displays: [VBDisplayDevice]) throws -> [VBDisplayDevice] {
        guard displays.map(\.id) == hardware.displayDevices.map(\.id) else {
            throw SavedSessionError.configurationChanged("The saved display identities are different.")
        }
        return try zip(displays, hardware.displayDevices).map {
            try $0.validatedLiveDisplay(replacing: $1, guestType: systemType)
        }
    }
}
