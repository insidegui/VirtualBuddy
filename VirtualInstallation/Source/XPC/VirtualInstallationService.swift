import Foundation
import os

@objc(VirtualInstallationService)
@_spi(VirtualInstallationService) public final class VirtualInstallationService: NSObject, VirtualInstallationServiceProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VirtualInstallationService.self))
    
    weak let clientConnection: NSXPCConnection!

    public init(clientConnection: NSXPCConnection) {
        self.clientConnection = clientConnection

        super.init()
    }

    private let backend: any DeviceRestoreBackend = {
        if ProcessInfo.virtualInstallationTestModeEnabled {
            TestDeviceRestoreBackend()
        } else {
            AppleMobileDeviceRestoreBackend()
        }
    }()

    private let _driver = OSAllocatedUnfairLock<DeviceRestoreDriver?>(initialState: nil)
    private var driver: DeviceRestoreDriver? {
        get { _driver.withLock { $0 } }
        set { _driver.withLock { $0 = newValue } }
    }

    private let _cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var cancelled: Bool {
        get { _cancelled.withLock { $0 } }
        set { _cancelled.withLock { $0 = newValue } }
    }

    // MARK: - Service -> Client

    private func send(_ state: DeviceRestoreState) {
        logger.debug("Sending state update to client: \(String(describing: state))")

        let proxy = clientConnection.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.fault("Remote object proxy error: \(error, privacy: .public)")
        }
        guard let client = proxy as? VirtualInstallationClientProtocol else {
            logger.fault("Client object proxy is of unexpected type")
            return
        }

        do {
            let payload = try PropertyListEncoder.xpc.encode(state)

            client.virtualMachineInstallationStateChanged(state: payload)
        } catch {
            logger.fault("Error encoding state update payload: \(error, privacy: .public)")
        }
    }

    // MARK: - Client -> Service

    public func startVirtualMachineInstallation(ecid: ECID, restoreBundleURL: URL, reply: @escaping @Sendable ((any Error)?) -> ()) {
        logger.notice("Installation requested for ECID \(ecid), bundle \(restoreBundleURL.safePath)")

        do {
            guard !cancelled else {
                throw NSError.viInstallationCancelled
            }
            guard driver == nil else {
                throw NSError.viInstallationConflict
            }

            do {
                let newDriver = try DeviceRestoreDriver(ecid: ecid, bundleURL: restoreBundleURL, backend: backend)

                self.driver = newDriver

                try newDriver.start { [weak self] state in
                    guard let self else { return }

                    send(state)

                    if state.outcome != nil {
                        terminate(reason: "Received final state update")
                    }
                }
            } catch {
                throw NSError.viFailedToStart(error)
            }
        } catch {
            logger.error("Start installation error: \(error, privacy: .public)")

            reply(error)
        }
    }

    public func cancelVirtualMachineInstallation(ecid: ECID, reply: @escaping @Sendable ((any Error)?) -> ()) {
        logger.notice("Cancellation requested for ECID \(ecid)")

        do {
            guard !cancelled else {
                throw NSError.viInstallationCancelled
            }
            guard driver != nil else {
                throw NSError.viInstallationNotStarted
            }

            reply(nil)

            terminate(reason: "Cancelled")
        } catch {
            logger.error("Cancel installation error: \(error, privacy: .public)")

            reply(error)
        }
    }

    public func terminate(reason: String) {
        logger.notice("Terminating for reason: \(reason, privacy: .public)")

        self.driver = nil
        self.clientConnection.invalidate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.logger.notice("Service terminating after cancellation")
            exit(0)
        }
    }
}

extension NSError {
    convenience init(viCode: Int, message: String, underlying: (any Error)? = nil) {
        var info: [String : Any] = [NSLocalizedFailureReasonErrorKey : message]
        if let underlying {
            info[NSUnderlyingErrorKey] = underlying
        }
        self.init(domain: kVirtualInstallationSubsystem, code: viCode, userInfo: info)
    }

    static let viDeviceNotFound = NSError(viCode: 1, message: "A device with the specified ECID could not be found.")
    static let viInstallationConflict = NSError(viCode: 2, message: "Attempting to start an installation after it has already started.")
    static let viInstallationCancelled = NSError(viCode: 3, message: "Installation was already cancelled.")
    static let viInstallationNotStarted = NSError(viCode: 4, message: "Installation was not started.")
    static func viFailedToStart(_ error: any Error) -> NSError { NSError(viCode: 5, message: "Failed to start installation.", underlying: error) }
}
