//
//  WHServiceListener.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 27/10/23.
//

import Foundation
import Network
import OSLog

@available(macOS 13.0, *)
final class WHServiceListener {
    private lazy var logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: String(describing: Self.self))

    let MTU = 65536
    let listener: NWListener
    private var queue: DispatchQueue

    init(port: __uint32_t) throws {
        var socketAdr = sockaddr_vm()
        socketAdr.svm_family = sa_family_t(AF_VSOCK)
        socketAdr.svm_len = __uint8_t(MemoryLayout<sockaddr_vm>.size)
        socketAdr.svm_port = port
        socketAdr.svm_cid = __uint32_t(VMADDR_CID_HOST)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let endpoint = withUnsafeBytes(of: socketAdr) { ptr in
            let addrPtr = ptr.assumingMemoryBound(to: sockaddr.self)
            return nw_endpoint_create_address(addrPtr.baseAddress!)
        }
        params.requiredLocalEndpoint = NWEndpoint.opaque(endpoint)
        params.allowLocalEndpointReuse = true

        self.listener = try NWListener(using: params)
        self.queue = DispatchQueue(label: "SocketListener-\(port)")
    }

    private var isActive = false

    func activate() {
        guard !isActive else { return }
        isActive = true

        logger.debug("Activate")

        self.listener.stateUpdateHandler = self.stateChanged(to:)
        self.listener.newConnectionHandler = self.connectionHandler(connection:)
        self.listener.start(queue: self.queue)
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false

        logger.debug("Invalidate")

        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func stateChanged(to newState: NWListener.State) {
        switch newState {
        case .setup:
            logger.debug("Setup")
        case .waiting:
            logger.debug("Waiting")
        case .ready:
            logger.debug("Ready")
            break
        case .failed(let error):
            logger.error("Error: \(error, privacy: .public)")
            self.invalidate()
        case .cancelled:
            logger.debug("Cancelled")
        @unknown default:
            logger.fault("Unknown listener state")
            assertionFailure("Unknown listener state: \(newState)")
        }
    }

    private func connectionHandler(connection: NWConnection) {
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                self.dataRxTx(of: connection)
            case .failed(_):
                connection.cancel()
            case .cancelled:
                print("\(connection) cancelled")
            default:
                break
            }
        }
        connection.start(queue: self.queue)
    }

    private func dataRxTx(of connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: MTU) { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }

            if let data = content {
                self.logger.debug("Received \(data.count, privacy: .public) byte(s)")
            }

            if let error = error {
                self.logger.error("Receive failure: \(error, privacy: .public)")
            }
        }
    }
}
