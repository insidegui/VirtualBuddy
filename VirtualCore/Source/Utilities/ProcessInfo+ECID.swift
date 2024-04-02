import Foundation
import IOKit

extension ProcessInfo {

    var machineECID: UInt64? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen")
        guard entry != MACH_PORT_NULL else { return nil }

        guard let ecidData = IORegistryEntrySearchCFProperty(entry, "IODeviceTree:/chosen", "unique-chip-id" as CFString, kCFAllocatorDefault, 0) as? Data else { return nil }

        guard ecidData.count > 0 else { return nil }

        return ecidData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt64? in
            guard let base = buffer.baseAddress else { return nil }
            return UnsafeRawPointer(base).load(as: UInt64.self)
        }
    }

}
