import AccessoryAccess
import Foundation
import Observation
import OSLog
import Virtualization

@available(macOS 27.0, *)
@Observable
@MainActor
public final class VMUSBDeviceController {
    public struct Device: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let vendorID: UInt16
        public let productID: UInt16
        public let productName: String?
        public let manufacturerName: String?
        public fileprivate(set) var isAttached: Bool
        public fileprivate(set) var isBusy: Bool
        public fileprivate(set) var errorMessage: String?

        fileprivate init(
            id: UInt64,
            vendorID: UInt16,
            productID: UInt16,
            productName: String?,
            manufacturerName: String?,
            isAttached: Bool = false,
            isBusy: Bool = false,
            errorMessage: String? = nil
        ) {
            self.id = id
            self.vendorID = vendorID
            self.productID = productID
            self.productName = productName
            self.manufacturerName = manufacturerName
            self.isAttached = isAttached
            self.isBusy = isBusy
            self.errorMessage = errorMessage
        }
    }

    public private(set) var devices = [Device]()
    public private(set) var registrationErrorMessage: String?

    @ObservationIgnored private let virtualMachine: VZVirtualMachine
    @ObservationIgnored private let configuredDevices: [VBUSBDevice]
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var accessories = [UInt64: AAUSBAccessory]()
    @ObservationIgnored private var passthroughDevices = [UInt64: VZUSBPassthroughDevice]()

    public init(
        virtualMachine: VZVirtualMachine,
        configuredDevices: [VBUSBDevice],
        logger: Logger
    ) {
        self.virtualMachine = virtualMachine
        self.configuredDevices = configuredDevices
        self.logger = logger
    }

    deinit {
        eventTask?.cancel()
    }

    public func start() {
        guard eventTask == nil else { return }
        registrationErrorMessage = nil

        eventTask = Task { [weak self] in
            do {
                let events = try await AAUSBAccessoryManager.shared.events(matching: [])

                for await event in events {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }

                    switch event {
                    case .didConnect(let accessory):
                        accessoryDidConnect(accessory)
                    case .didDisconnect(let accessory):
                        accessoryDidDisconnect(accessory)
                    @unknown default:
                        logger.debug("Ignoring an unknown USB accessory event")
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.registrationErrorMessage = error.localizedDescription
                self?.logger.error("Failed to monitor USB accessories: \(error, privacy: .public)")
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        accessories.removeAll()
        passthroughDevices.removeAll()
        devices.removeAll()
    }

    public func toggleAttachment(for deviceID: Device.ID) async throws {
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            throw Failure("The USB device is no longer available.")
        }

        if device.isAttached {
            try await detach(deviceID: deviceID)
        } else {
            try await attach(deviceID: deviceID)
        }
    }

    private func accessoryDidConnect(_ accessory: AAUSBAccessory) {
        guard let device = makeDevice(for: accessory) else {
            logger.error("Ignoring USB accessory with an invalid device descriptor (registry ID: \(accessory.registryID))")
            return
        }

        accessories[device.id] = accessory
        upsert(device)

        guard configuredDevices.contains(where: { $0.id == VBUSBDevice.ID(vendorID: device.vendorID, productID: device.productID) }) else {
            return
        }

        Task { [weak self] in
            do {
                try await self?.attach(deviceID: device.id)
            } catch {
                self?.logger.error("Failed to automatically attach USB device: \(error, privacy: .public)")
            }
        }
    }

    private func accessoryDidDisconnect(_ accessory: AAUSBAccessory) {
        accessories[accessory.registryID] = nil
        passthroughDevices[accessory.registryID] = nil
        devices.removeAll { $0.id == accessory.registryID }
    }

    private func attach(deviceID: Device.ID) async throws {
        guard let accessory = accessories[deviceID] else {
            throw Failure("The USB device is no longer available.")
        }
        guard passthroughDevices[deviceID] == nil else { return }
        guard let controller = virtualMachine.usbControllers.first else {
            throw Failure("The virtual machine doesn't have a USB controller.")
        }

        updateDevice(deviceID) {
            $0.isBusy = true
            $0.errorMessage = nil
        }

        do {
            let configuration = VZUSBPassthroughDeviceConfiguration(device: accessory)
            let passthroughDevice = try VZUSBPassthroughDevice(configuration: configuration)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.attach(device: passthroughDevice) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            passthroughDevices[deviceID] = passthroughDevice
            updateDevice(deviceID) {
                $0.isAttached = true
                $0.isBusy = false
            }
        } catch {
            updateDevice(deviceID) {
                $0.isBusy = false
                $0.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    private func detach(deviceID: Device.ID) async throws {
        guard let passthroughDevice = passthroughDevices[deviceID],
              let controller = passthroughDevice.usbController
        else {
            passthroughDevices[deviceID] = nil
            updateDevice(deviceID) { $0.isAttached = false }
            return
        }

        updateDevice(deviceID) {
            $0.isBusy = true
            $0.errorMessage = nil
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.detach(device: passthroughDevice) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            passthroughDevices[deviceID] = nil
            updateDevice(deviceID) {
                $0.isAttached = false
                $0.isBusy = false
            }
        } catch {
            updateDevice(deviceID) {
                $0.isBusy = false
                $0.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    private func makeDevice(for accessory: AAUSBAccessory) -> Device? {
        let discoveredDevice = VBHostUSBDeviceDiscovery.device(registryID: accessory.registryID)
        let identifiers = discoveredDevice.map { ($0.vendorID, $0.productID) }
            ?? identifiers(from: accessory.deviceDescriptorData)

        guard let identifiers else { return nil }

        let configuredName = configuredDevices.first {
            $0.vendorID == identifiers.0 && $0.productID == identifiers.1
        }?.name

        return Device(
            id: accessory.registryID,
            vendorID: identifiers.0,
            productID: identifiers.1,
            productName: discoveredDevice?.productName ?? configuredName,
            manufacturerName: discoveredDevice?.manufacturerName,
            isAttached: passthroughDevices[accessory.registryID] != nil
        )
    }

    private func identifiers(from descriptor: Data) -> (UInt16, UInt16)? {
        guard descriptor.count >= 12 else { return nil }

        return descriptor.withUnsafeBytes { bytes in
            let vendorID = bytes.loadUnaligned(fromByteOffset: 8, as: UInt16.self).littleEndian
            let productID = bytes.loadUnaligned(fromByteOffset: 10, as: UInt16.self).littleEndian
            return (vendorID, productID)
        }
    }

    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }

        devices.sort { lhs, rhs in
            let lhsName = lhs.productName ?? ""
            let rhsName = rhs.productName ?? ""
            let nameOrder = lhsName.localizedStandardCompare(rhsName)
            return nameOrder == .orderedSame ? lhs.id < rhs.id : nameOrder == .orderedAscending
        }
    }

    private func updateDevice(_ deviceID: Device.ID, update: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        update(&devices[index])
    }
}
