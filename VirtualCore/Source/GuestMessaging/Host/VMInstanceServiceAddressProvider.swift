import Cocoa
import Foundation
@preconcurrency import Virtualization
import OSLog
import VirtualMessagingTransport
import VirtualMessagingService

final class VMInstanceServiceAddressProvider: VMServiceAddressProvider, @unchecked Sendable {
    private let queue = DispatchQueue(label: "VMInstanceServiceAddressProvider", target: .global())

    private let logger: Logger
    private weak var _device: VZVirtioSocketDevice? {
        didSet {
            #if DEBUG
            if _device != oldValue, _device == nil {
                logger.debug("🎯 My socket device is gone")
            }
            #endif
        }
    }

    let name: String
    private let storage: Storage

    init(device: VZVirtioSocketDevice, name: String) {
        self._device = device
        self.name = name
        self.logger = Logger(subsystem: kVirtualMessagingSubsystem, category: "AddressProvider(\(name))")
        self.storage = Storage(logger: logger)
    }

    private var device: VZVirtioSocketDevice {
        get throws {
            guard let _device else {
                throw "Socket device not available."
            }
            return _device
        }
    }

    private final actor Storage {
        let logger: Logger

        init(logger: Logger) {
            self.logger = logger
        }

        private var addressTasks = [UUID: Task<BindAddress, Error>]()
        private var connections = [VZVirtioSocketConnection]() {
            didSet {
                #if DEBUG
                let count = connections.count
                let desc = connections.map({ "\($0.fileDescriptor)" }).joined(separator: ", ")
                logger.debug("🎯 Connections (\(count, privacy: .public)): \(desc)")
                #endif
            }
        }

        func add(_ connection: VZVirtioSocketConnection) {
            connections.append(connection)
        }

        func add(_ task: Task<BindAddress, Error>, id: UUID) {
            addressTasks[id] = task
        }

        func remove(_ taskID: UUID) {
            addressTasks[taskID] = nil
        }

        func invalidate() {
            connections.removeAll()
            addressTasks.values.forEach { $0.cancel() }
            addressTasks.removeAll()
        }
    }

    private func runAddressTask(_ closure: @escaping @Sendable () async throws -> BindAddress) async throws(VMServiceConnectionError) -> BindAddress {
        let task = Task {
            try await closure()
        }

        let taskID = UUID()
        await storage.add(task, id: taskID)

        do {
            let result = try await task.value

            await storage.remove(taskID)

            return result
        } catch let error as VMServiceConnectionError {
            await storage.remove(taskID)

            throw error
        } catch {
            await storage.remove(taskID)

            throw .addressLookupFailure("\(error)")
        }
    }

    public func address(forServiceID serviceID: String, portNumber: UInt32) async throws(VMServiceConnectionError) -> BindAddress {
        try await runAddressTask { [weak self] in
            guard let self else { throw CancellationError() }

            do {
                let connection = try await waitForConnection(toPort: portNumber)

                await storage.add(connection)

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

    func invalidate() async {
        await storage.invalidate()
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
