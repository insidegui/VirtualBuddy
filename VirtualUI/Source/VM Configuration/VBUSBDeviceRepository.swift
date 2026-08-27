import SwiftUI
import Observation
import OSLog
import USBIDKit
import VirtualCore

@Observable
@MainActor
public final class VBUSBDeviceRepository {
    private let logger = Logger(for: VBUSBDeviceRepository.self)

    public static let shared = VBUSBDeviceRepository()

    private var database: USBIDDatabase = USBIDDatabase(configuration: .virtualBuddy)

    private init() { }

    private var updateTask: Task<Void, Never>?

    public func updateIfNeeded() {
        guard updateTask == nil else { return }

        updateTask = Task {
            defer { updateTask = nil }

            do {
                self.database = try await database.refreshed()
            } catch {
                logger.warning("Database update failed: \(error, privacy: .public)")
            }
        }
    }

    public func device(vendorID: UInt16, productID: UInt16) -> VBUSBDevice {
        VBUSBDevice(
            vendorID: vendorID,
            productID: productID,
            name: database.deviceDisplayName(vendorID: vendorID, productID: productID)
        )
    }
}

private extension USBIDDatabase {
    func deviceDisplayName(vendorID: UInt16, productID: UInt16) -> String {
        let result = lookup(vendorID: vendorID, productID: productID)

        return switch result {
        case .vendorOnly(let vendor): "\(vendor.displayName) Device"
        case .product(_, let product): product.name
        case nil: "USB Device"
        }
    }
}

private extension USBIDConfiguration {
    static let virtualBuddy = USBIDConfiguration(
        databaseURL: VBAPIClient.Environment.current.usbIDURL,
        cacheDirectoryURL: URL.defaultVirtualBuddyLibraryURL
    )
}
