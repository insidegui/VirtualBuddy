import Cocoa
import Foundation
@preconcurrency import Virtualization
import OSLog
import VirtualMessagingTransport
import VirtualMessagingService

final class VMInstanceServiceAddressProvider: VMServiceAddressProvider, @unchecked Sendable {
    private let logger: Logger
    private weak var _device: VZVirtioSocketDevice?

    let name: String

    init(device: VZVirtioSocketDevice, name: String) {
        self._device = device
        self.name = name
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "AddressProvider(\(name))")
    }

    private var device: VZVirtioSocketDevice {
        get throws {
            guard let _device else {
                throw "Socket device not available."
            }
            return _device
        }
    }

    nonisolated(unsafe) private var _addressTasks = OSAllocatedUnfairLock(initialState: [UUID: Task<BindAddress, Error>]())
    private var addressTasks: [UUID: Task<BindAddress, Error>] {
        get { _addressTasks.withLock { $0 } }
        set { _addressTasks.withLock { $0 = newValue } }
    }

    nonisolated(unsafe) private var _connections = OSAllocatedUnfairLock(initialState: [VZVirtioSocketConnection]())
    private var connections: [VZVirtioSocketConnection] {
        get { _connections.withLock { $0 } }
        set {
            _connections.withLock {
                $0 = newValue
                let count = $0.count
                logger.debug("Connections: \(count, privacy: .public)")
            }
        }
    }

    private func runAddressTask(_ closure: @escaping @Sendable () async throws -> BindAddress) async throws(VMServiceConnectionError) -> BindAddress {
        let task = Task {
            try await closure()
        }

        let taskID = UUID()
        addressTasks[taskID] = task
        defer { addressTasks[taskID] = nil }

        do {
            return try await task.value
        } catch let error as VMServiceConnectionError {
            throw error
        } catch {
            throw .addressLookupFailure("\(error)")
        }
    }

    public func address(forServiceID serviceID: String, portNumber: UInt32) async throws(VMServiceConnectionError) -> BindAddress {
        try await runAddressTask { [weak self] in
            guard let self else { throw CancellationError() }

            do {
                let connection = try await waitForConnection(toPort: portNumber)

                connections.append(connection)

                return .fileDescriptor(connection.fileDescriptor)
            } catch {
                throw VMServiceConnectionError.addressLookupFailure("\(error)")
            }
        }
    }

    private func waitForConnection(toPort port: UInt32) async throws -> VZVirtioSocketConnection {
        logger.debug("Request wait for connection to \(port)")

        var lastPortConnectionAttemptLogDate = Date.distantPast

        while true {
            try Task.checkCancellation()

            try await Task.sleep(for: .milliseconds(500))

            do {
                let connection = try await device.vbConnect(toPort: port)

                logger.notice("Established low-level virtual connection to port \(port)")

                return connection
            } catch {
                if Date.now.timeIntervalSince(lastPortConnectionAttemptLogDate) >= 3 {
                    logger.warning("Port \(port) not available yet, waiting...")
                    lastPortConnectionAttemptLogDate = .now
                }
            }

            await Task.yield()
        }
    }

    func invalidate() {
        addressTasks.values.forEach { $0.cancel() }
        addressTasks.removeAll()

        connections.removeAll()
    }

    deinit {
        #if DEBUG
        print("[ADDRESS PROVIDER] \(name) Bye bye 👋")
        #endif
    }
}

@_spi(GuestDebug) public extension VMInstance {
    var socketDevice: VZVirtioSocketDevice {
        get throws {
            let vm = try ensureVM()
            guard let device = vm.socketDevices.compactMap({ $0 as? VZVirtioSocketDevice }).first else {
                throw "Socket device not available."
            }
            return device
        }
    }

    @discardableResult
    func bootstrapGuestServiceClients() throws -> HostAppServices {
        let provider = try VMInstanceServiceAddressProvider(device: socketDevice, name: name)
        let coordinator = GuestServicesCoordinator(addressProvider: provider, isListener: false)

        _addressProvider = provider
        _services = HostAppServices(coordinator: coordinator)

        return try services.activate()
    }
}

private extension VZVirtioSocketDevice {
    func vbConnect(toPort port: UInt32) async throws -> VZVirtioSocketConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.connect(toPort: port) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }
}
