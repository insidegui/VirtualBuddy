import Foundation
import OSLog
@testable import VirtualWormhole

/// Vends a mach service that VirtualBuddy can connect to in order to handle socket communication with guests.
final class WHXPCService {

    static let shared = WHXPCService()

    private init() { }

    let logger = Logger(for: WHXPCService.self)

    private var listener: xpc_connection_t!

    private var connections = [ObjectIdentifier: WHXPCServiceConnection]()

    func activate() {
        listener = xpc_connection_create_mach_service(VirtualWormholeConstants.whRemoteXPCServiceName, .main, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))

        xpc_connection_set_event_handler(listener) { [weak self] object in
            guard let self else { return }

            if xpc_get_type(object) == XPC_TYPE_CONNECTION {
                logger.log("XPC connection received: \(xpc_description(object))")

                let xpcConnection = WHXPCServiceConnection(xpcConnection: object) { [weak self] xpcConnection in
                    guard let self else { return }
                    self.connections[ObjectIdentifier(xpcConnection)] = nil
                }

                self.connections[ObjectIdentifier(xpcConnection)] = xpcConnection

                xpcConnection.activate()
            } else if xpc_get_type(object) == XPC_TYPE_ERROR {
                logger.warning("XPC error: \(xpc_description(object))")
            } else {
                logger.fault("Unhandled XPC event: \(xpc_description(object))")
            }
        }

        xpc_connection_activate(listener)

        logger.log("Waiting for XPC connections")
    }

}

/// Handles a single host <> guest client socket from the VirtualBuddy app.
final class WHXPCServiceConnection {
    let logger = Logger(for: WHXPCServiceConnection.self)

    let xpcConnection: xpc_connection_t
    private var guestConnection: WHInAppGuestConnection!
    private let invalidationHandler: (WHXPCServiceConnection) -> Void

    init(xpcConnection: xpc_connection_t, invalidationHandler: @escaping (WHXPCServiceConnection) -> Void) {
        self.xpcConnection = xpcConnection
        self.invalidationHandler = invalidationHandler
    }

    func activate() {
        xpc_connection_set_event_handler(xpcConnection) { [weak self] message in
            guard let self else { return }

            if xpc_get_type(message) == XPC_TYPE_DICTIONARY {
                logger.log("Received XPC message: \(xpc_description(message))")

                let action = xpc_dictionary_get_uint64(message, "action")

                switch action {
                case 0:
                    logger.log("Received action 0, activating transport")

                    invalidateGuestConnection()

                    do {
                        let fd = xpc_dictionary_dup_fd(message, "fd")

                        guard fd > 0 else {
                            throw WHError("Missing or invalid file descriptor")
                        }

                        setupGuestConnection(with: fd)
                    } catch {
                        logger.error("Transport activation failed: \(error, privacy: .public)")
                    }
                case 1:
                    logger.log("Received action 1, tearing down transport")

                    invalidateGuestConnection()
                default:
                    logger.error("Unknown action \(action)")
                }
            } else if xpc_get_type(message) == XPC_TYPE_ERROR {
                logger.warning("XPC connection error: \(xpc_description(message))")

                invalidate()
            }
        }

        xpc_connection_activate(xpcConnection)
    }

    private func setupGuestConnection(with fileDescriptor: Int32) {
        logger.debug("Setting up guest connection with \(fileDescriptor)")

        let newConnection = WHInAppGuestConnection()
        self.guestConnection = newConnection

        Task {
            do {
                try await newConnection.connect(using: fileDescriptor) { [weak self] _ in
                    guard let self else { return }

                    logger.log("Guest connection invalidated")

                    invalidate()
                }
            } catch {
                logger.error("Guest connection failed: \(error, privacy: .public)")

                invalidate()
            }
        }
    }

    private func invalidateGuestConnection() {
        guestConnection?.invalidate()
        guestConnection = nil
    }

    private func invalidate() {
        invalidateGuestConnection()

        xpc_connection_cancel(xpcConnection)

        invalidationHandler(self)
    }
}
