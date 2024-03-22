import Foundation
import OSLog
import Combine
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

/// Runs a socket client for the guest server in a separate XPC service.
/// This allows for faster iteration since it's possible to develop new features without
/// having to constantly shut down VMs and restart the VirtualBuddy app itself.
final class WHXPCGuestConnection: WHGuestConnection {
    private let logger = Logger(for: WHXPCGuestConnection.self)

    private var xpcConnection: xpc_connection_t?

    private var invalidationHandler: ((WHXPCGuestConnection) -> Void)?

    func connect(using fileDescriptor: Int32, invalidationHandler: @escaping (WHXPCGuestConnection) -> Void) async throws {
        self.invalidationHandler = invalidationHandler

        let connection = xpc_connection_create_mach_service(VirtualWormholeConstants.whRemoteXPCServiceName, .main, 0)
        self.xpcConnection = connection

        xpc_connection_set_event_handler(connection) { [weak self] message in
            guard let self else { return }

            if xpc_get_type(message) == XPC_TYPE_ERROR {
                logger.warning("XPC connection error: \(xpc_description(message))")

                invalidate()
            } else {
                logger.warning("Unhandled XPC message: \(xpc_description(message))")
            }
        }

        xpc_connection_activate(connection)

        let fd = xpc_fd_create(fileDescriptor)

        let dict = xpc_dictionary_create_empty()
        xpc_dictionary_set_uint64(dict, "action", 0)
        xpc_dictionary_set_value(dict, "fd", fd)

        logger.debug("Sending connection message to remote service")

        xpc_connection_send_message(connection, dict)
    }

    func invalidate() {        
        guard let xpcConnection else { return }

        logger.debug(#function)

        xpc_connection_cancel(xpcConnection)
        self.xpcConnection = nil

        invalidationHandler?(self)
    }
}

func xpc_description(_ obj: xpc_object_t) -> String {
    String(cString: xpc_copy_description(obj))
}
