import Foundation
import IOKit

public struct VBHostUSBDevice: Identifiable, Hashable, Sendable {
    public let id: UInt64
    public let vendorID: UInt16
    public let productID: UInt16
    public let productName: String?
    public let manufacturerName: String?

    public init(
        id: UInt64,
        vendorID: UInt16,
        productID: UInt16,
        productName: String?,
        manufacturerName: String?
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.productName = productName
        self.manufacturerName = manufacturerName
    }
}

public enum VBHostUSBDeviceDiscovery {
    public static func connectedDevices() -> [VBHostUSBDevice] {
        var iterator: io_iterator_t = 0

        guard let matching = IOServiceMatching("IOUSBHostDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            return []
        }

        defer { IOObjectRelease(iterator) }

        var devices = [VBHostUSBDevice]()
        var service = IOIteratorNext(iterator)

        while service != 0 {
            if let device = device(for: service) {
                devices.append(device)
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return devices.sorted { lhs, rhs in
            let lhsName = lhs.productName ?? ""
            let rhsName = rhs.productName ?? ""
            let nameOrder = lhsName.localizedStandardCompare(rhsName)

            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            if lhs.vendorID != rhs.vendorID {
                return lhs.vendorID < rhs.vendorID
            }
            if lhs.productID != rhs.productID {
                return lhs.productID < rhs.productID
            }
            return lhs.id < rhs.id
        }
    }

    public static func device(registryID: UInt64) -> VBHostUSBDevice? {
        guard let matching = IORegistryEntryIDMatching(registryID) else { return nil }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }

        defer { IOObjectRelease(service) }

        return device(for: service)
    }

    private static func device(for service: io_registry_entry_t) -> VBHostUSBDevice? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?

        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
        let vendorNumber = properties["idVendor"] as? NSNumber,
        let productNumber = properties["idProduct"] as? NSNumber
        else {
            return nil
        }

        let deviceClass = (properties["bDeviceClass"] as? NSNumber)?.uint8Value
        guard deviceClass != 9 else { return nil }

        var registryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else {
            return nil
        }

        return VBHostUSBDevice(
            id: registryID,
            vendorID: vendorNumber.uint16Value,
            productID: productNumber.uint16Value,
            productName: stringProperty(named: "kUSBProductString", legacyName: "USB Product Name", in: properties),
            manufacturerName: stringProperty(named: "kUSBVendorString", legacyName: "USB Vendor Name", in: properties)
        )
    }

    private static func stringProperty(
        named name: String,
        legacyName: String,
        in properties: [String: Any]
    ) -> String? {
        let value = (properties[name] as? String) ?? (properties[legacyName] as? String)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
