import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

/// Coordinates access to guest services on both sides of the connection.
public final class GuestServicesCoordinator: @unchecked Sendable, ObservableObject {
    private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestServerCoordinator")

    /// Server for virtualized guest, which is used when VirtualBuddyGuest is running in a virtual machine.
    private static let guestServer = GuestServicesCoordinator(addressProvider: VSockVMServiceAddressProvider(), isListener: true)

    #if DEBUG
    /// [DEBUG ONLY] Server for simulated guest, which is used when VirtualBuddyGuest is running on the host for testing.
    private static let simulatedGuestServer = GuestServicesCoordinator(addressProvider: SimulatedGuestAddressProvider(shouldDeleteExistingSocket: true), isListener: true)

    /// [DEBUG ONLY] Host-side client for simulated guest-side server, which is used when VirtualBuddy is running with guest simulation enabled.
    internal static let simulatedHostClient = GuestServicesCoordinator(addressProvider: SimulatedGuestAddressProvider(shouldDeleteExistingSocket: false), isListener: false)
    #endif

    /// The global services coordinator instance, which is automatically set up depending on the environment.
    public static let current: GuestServicesCoordinator = {
        if ProcessInfo.processInfo.isVirtualBuddyGuest {
            #if DEBUG
            if UserDefaults.isGuestSimulationEnabled {
                return .simulatedGuestServer
            } else {
                return .guestServer
            }
            #else
            return .guestServer
            #endif
        } else {
            #if DEBUG
            if UserDefaults.isGuestSimulationEnabled {
                return .simulatedHostClient
            } else {
                fatalError("GuestServicesCoordinator.current singleton can't be used on the host unless guest simulation is enabled")
            }
            #else
            fatalError("GuestServicesCoordinator.current singleton can't be used on the host unless guest simulation is enabled")
            #endif
        }
    }()

    private let addressProvider: VMServiceAddressProvider
    private let coordinator: VMServiceCoordinator

    /// On the host side, this initializer will be used, since each VM instance will need its own services coordinator.
    /// The guest always uses the ``current`` singleton, as there can only be a single guest app per VM.
    public init(addressProvider: VMServiceAddressProvider, isListener: Bool) {
        self.addressProvider = addressProvider
        self.coordinator = VMServiceCoordinator(isListener: isListener, addressProvider: addressProvider)
    }

    private let bootstrappedServices = NSMapTable<NSString, GuestServiceInstance>(keyOptions: .objectPersonality, valueOptions: .strongMemory)

    @MainActor
    @Published public private(set) var hasConnection = false

    public func activate() async throws {
        let coordinatorAddress = try await addressProvider.address(
            forServiceID: kVMServiceCoordinatorServiceID,
            portNumber: kVMServiceCoordinatorPortNumber
        )

        logger.debug("Activate with coordinator address \(coordinatorAddress)")

        Task {
            for await hasConnection in await coordinator.isPeerConnected() {
                await MainActor.run {
                    self.hasConnection = hasConnection
                }

                if !hasConnection {
                    bootstrappedServices.removeAllObjects()
                }
            }
        }

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

        try await instance.activate(channelProvider: coordinator, isListener: coordinator.isListener)
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
