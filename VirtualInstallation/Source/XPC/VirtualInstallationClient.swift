import Foundation
import Combine
import os

@objc(VirtualInstallationClient)
final class VirtualInstallationClient: NSObject, VirtualInstallationClientProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VirtualInstallationClient.self))

    enum Failure: Error, Sendable {
        case connectionInvalidated
        case connectionInterrupted
        case invalidService
        case serialization
        case service(_ error: Error)
    }

    enum Event: Sendable {
        case stateChanged(_ state: DeviceRestoreState)
        case connectionFailed(_ error: Failure)

        var isStateChanged: Bool {
            if case .stateChanged = self {
                true
            } else {
                false
            }
        }
    }

    private let _invalidated = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var invalidated: Bool {
        get { _invalidated.withLock { $0 } }
        set { _invalidated.withLock { $0 = newValue } }
    }

    private let id = UUID()

    private let eventSubject = PassthroughSubject<Event, Never>()
    var eventPublisher: AnyPublisher<Event, Never> { eventSubject.eraseToAnyPublisher() }

    // MARK: - Lifecycle

    private let _connectionLock = OSAllocatedUnfairLock<NSXPCConnection?>(uncheckedState: nil)
    private var _connection: NSXPCConnection? {
        get { _connectionLock.withLockUnchecked { $0 } }
        set { _connectionLock.withLockUnchecked { $0 = newValue } }
    }

    private func createConnection() throws -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: kVirtualInstallationServiceName)

        connection.remoteObjectInterface = NSXPCInterface(with: VirtualInstallationServiceProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: VirtualInstallationClientProtocol.self)
        connection.exportedObject = self

        connection.invalidationHandler = { [weak self] in
            self?.send(.connectionFailed(.connectionInvalidated))
            self?.invalidated = true
        }
        connection.interruptionHandler = { [weak self] in
            self?.send(.connectionFailed(.connectionInterrupted))
            self?.invalidated = true
        }

        connection.setVirtualInstallationCodeSigningRequirement()

        try connection.__vi_safeSetInstanceUUID(id)

        return connection
    }

    private func withService(perform block: @escaping (Result<VirtualInstallationServiceProtocol, Failure>) -> ()) {
        let connection: NSXPCConnection
        if let _connection {
            connection = _connection
        } else {
            do {
                connection = try createConnection()
                _connection = connection

                connection.activate()
            } catch {
                block(.failure(.service(error)))
                return
            }
        }

        guard let service = connection.remoteObjectProxy as? VirtualInstallationServiceProtocol else {
            block(.failure(.invalidService))
            return
        }

        block(.success(service))
    }

    private func send(_ event: Event) {
        DispatchQueue.main.async { [self] in
            /// Allow state changed events to go through even when invalidated, as we must report
            /// a final state event for the installer to report its completion and it may occur shortly after
            /// the service instance has already been invalidated.
            guard event.isStateChanged || !invalidated else { return }
            eventSubject.send(event)
        }
    }

    // MARK: - Client -> Server

    func startVirtualMachineInstallation(
        ecid: ECID,
        restoreBundleURL: URL,
        simulateFailure: Bool,
        completion: @escaping @Sendable (_ error: Error?) -> ()
    ) {
        logger.debug("Start for ECID \(ecid), bundle \(restoreBundleURL.safePath), simulate failure: \(simulateFailure)")

        withService { [weak self] result in
            do {
                let service = try result.get()

                service.startVirtualMachineInstallation(
                    ecid: ecid,
                    restoreBundleURL: restoreBundleURL,
                    simulateFailure: simulateFailure
                ) { [weak self] error in
                    if let error {
                        self?.logger.error("Received startVirtualMachineInstallation reply with error: \(error, privacy: .public)")
                    } else {
                        self?.logger.notice("Received startVirtualMachineInstallation reply")
                    }

                    completion(error)
                }
            } catch {
                completion(error)
            }
        }
    }

    func cancelVirtualMachineInstallation(ecid: ECID, completion: @escaping @Sendable (_ error: Error?) -> ()) {
        logger.debug("Cancel for ECID \(ecid)")

        invalidated = true

        withService { [weak self] result in
            do {
                let service = try result.get()

                service.cancelVirtualMachineInstallation(ecid: ecid) { [weak self] error in
                    if let error {
                        self?.logger.error("Received cancelVirtualMachineInstallation reply with error: \(error, privacy: .public)")
                    } else {
                        self?.logger.notice("Received cancelVirtualMachineInstallation reply")
                    }

                    completion(error)
                }
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - Server -> Client

    func virtualMachineInstallationStateChanged(state: Data) {
        do {
            let decodedState = try PropertyListDecoder.xpc.decode(DeviceRestoreState.self, from: state)

            send(.stateChanged(decodedState))
        } catch {
            logger.fault("Error decoding state update payload: \(error, privacy: .public)")

            send(.connectionFailed(.serialization))
        }
    }
}
