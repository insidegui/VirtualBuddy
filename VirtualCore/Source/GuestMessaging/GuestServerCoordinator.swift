import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

/// Guest-side services bootstrap.
public final class GuestServerCoordinator: Sendable {
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestServerCoordinator")

    /// Server for virtualized guest, which is used when VirtualBuddyGuest is running in a virtual machine.
    public static let virtualizedGuest = GuestServerCoordinator(addressProvider: VSockVMServiceAddressProvider())

    #if DEBUG
    /// [DEBUG ONLY] Server for simulated guest, which is used when VirtualBuddyGuest is running on the host for testing.
    public static let simulatedGuest = GuestServerCoordinator(addressProvider: SimulatedGuestAddressProvider(shouldDeleteExistingSocket: true))
    #endif

    private let addressProvider: VMServiceAddressProvider
    private let coordinator: VMServiceCoordinator

    internal init(addressProvider: VMServiceAddressProvider) {
        self.addressProvider = addressProvider
        self.coordinator = VMServiceCoordinator(isListener: true, addressProvider: addressProvider)
    }

    private let bootstrappedServices = NSMapTable<NSString, GuestServiceInstance>(keyOptions: .objectPersonality, valueOptions: .strongMemory)

    public func activate() async throws {
        let coordinatorAddress = addressProvider.address(
            forServiceID: kVMServiceCoordinatorServiceID,
            portNumber: kVMServiceCoordinatorPortNumber
        )

        logger.debug("Activate with coordinator address \(coordinatorAddress)")

        try await coordinator.activate(address: coordinatorAddress)
    }
    
    /// Bootstraps and activates a guest service.
    /// - Parameter service: The service to activate.
    ///
    /// When called with an instance of a ``GuestService`` subclass, this method will perform
    /// the necessary actions to get the service registered with the services coordinator.
    ///
    /// On the guest, this means obtaining a bind address and starting up a server.
    /// On the host, this means looking up the service with the remote coordinator and creating a connection to it.
    ///
    /// Once those steps are finalized, the service's ``GuestService/bootstrapCompleted()`` method will be called,
    /// at which point the service may safely use ``GuestService/receive(_:using:)`` to configure its message routes.
    public func bootstrap<S: GuestService>(service: S) async throws {
        guard bootstrappedServices.object(forKey: service.id as NSString) == nil else {
            throw "Attempting to bootstrap \"\(service.id)\" more than once."
        }

        let instance = GuestServiceInstance(service: service)

        bootstrappedServices.setObject(instance, forKey: service.id as NSString)

        try await instance.activate(channelProvider: coordinator)
    }
}

extension NSMapTable: @retroactive @unchecked Sendable { }

// MARK: - Debugging Support

#if DEBUG
internal struct SimulatedGuestAddressProvider: VMServiceAddressProvider {
    private static let baseURL: URL = {
        do {
            let url = URL.defaultVirtualBuddyLibraryURL
                .appending(path: "SimulatedGuest", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        } catch {
            fatalError("\(error)")
        }
    }()

    let shouldDeleteExistingSocket: Bool

    func address(forServiceID serviceID: String, portNumber: UInt32) -> BindAddress {
        let path = Self.baseURL.appending(path: "\(portNumber).sock").path
        if shouldDeleteExistingSocket, FileManager.default.fileExists(atPath: path) {
            try! FileManager.default.removeItem(atPath: path)
        }
        return BindAddress.unixDomainSocket(path: path)
    }
}
#endif
