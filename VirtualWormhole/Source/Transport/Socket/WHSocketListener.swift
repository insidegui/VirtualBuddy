import Foundation
import OSLog

struct WHError: LocalizedError {
    var errorDescription: String?
    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}

/// Used by the guest to listen for connections from the host.
/// Has a `Connection` type that can be used by both guests and host.
final class WHSocket {
    
    typealias ClientID = Int32
    
    typealias EventStream = AsyncThrowingStream<Event, Error>
    typealias ByteStream = AsyncThrowingStream<UInt8, Error>
    
    enum Event: CustomStringConvertible {
        case activated
        case invalidated
        case connected(Connection)
        case disconnected
    }

    let port: UInt32
    private var socketDescriptor: Int32?
    private(set) var eventStream: EventStream
    private var eventContinuation: EventStream.Continuation
    private let queue: DispatchQueue
    private(set) var connection: Connection?
    private let logger: Logger
    
    init(port: UInt32) {
        let name = "WHSocketListener-\(port)"
        self.port = port
        (eventStream, eventContinuation) = EventStream.makeStream()
        self.queue = DispatchQueue(label: name, qos: .userInitiated)
        self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: name)
    }
    
    private var isValid = false

    @discardableResult
    func activate() -> EventStream {
        guard !isValid else { return eventStream }
        isValid = true
        
        (eventStream, eventContinuation) = EventStream.makeStream()
        
        logger.debug("Activate")
        
        queue.async { [weak self] in
            self?.onQueueRunSocket()
        }
        
        return eventStream
    }
    
    func invalidate() {
        guard isValid else { return }
        isValid = false
        
        logger.debug("Invalidate")

        connectionWaitWorkItem?.cancel()
        connectionWaitWorkItem = nil
        
        connection?.invalidate()
        connection = nil
        
        if let socketDescriptor {
            Darwin.close(socketDescriptor)
        }
        
        eventContinuation.yield(.invalidated)
    }
    
    deinit {
        logger.debug("Bye Bye")
    }
    
    /// Represents a client that's currently connected to the server.
    final class Connection: CustomStringConvertible {
        let id: String
        let stream: ByteStream
        private let handle: FileHandle
        private let logger: Logger
        private let internalStream: FileHandle.AsyncBytes
        private let byteContinuation: ByteStream.Continuation
        private let invalidationHandler: (Error?) -> Void
        
        init(serverPort: UInt32, clientDescriptor: ClientID, invalidationHandler: @escaping (Error?) -> Void) {
            self.id = "Connection-\(serverPort)-\(clientDescriptor)"
            self.logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: id)
            self.handle = FileHandle(fileDescriptor: clientDescriptor)
            self.internalStream = handle.bytes
            (stream, byteContinuation) = ByteStream.makeStream()
            self.invalidationHandler = invalidationHandler
        }
        
        private var streamingTask: Task<Void, Never>?
        
        func activate() {
            guard streamingTask == nil else { return }
            
            logger.debug("Activate")
            
            streamingTask = Task.detached { [weak self] in
                guard let self else { return }
                await self.runStream()
            }
        }
        
        func invalidate() {
            logger.debug("Invalidate")
            
            streamingTask?.cancel()
            streamingTask = nil
            
            do {
                try handle.close()
            } catch {
                logger.warning("Failed to close socket file handle: \(error, privacy: .public)")
            }
        }

        func write(_ data: Data) throws {
            try handle.write(contentsOf: data)
        }

        private func runStream() async {
            logger.debug("Run stream")
            
            do {
                for try await byte in internalStream {
                    guard !Task.isCancelled else { break }
                    
                    byteContinuation.yield(byte)
                }
                
                logger.debug("Byte stream ended")
                
                invalidationHandler(nil)
            } catch {
                logger.warning("Byte stream interrupted: \(error, privacy: .public)")
                
                invalidationHandler(error)
            }
        }
        
        deinit {
            logger.debug("Bye Bye")
        }
    }
    
    // MARK: - Private API
    
    private func onQueueRunSocket() {
        logger.debug("Run socket")
        
        do {
            let fd = Darwin.socket(AF_VSOCK, SOCK_STREAM, 0)
            guard fd >= 0 else { throw WHError("Failed to create socket file descriptor.")}
            
            self.socketDescriptor = fd
            
            let addr: sockaddr_vm = {
                var a = sockaddr_vm()
                a.svm_family = sa_family_t(AF_VSOCK)
                a.svm_port = self.port
                a.svm_cid = UInt32(VMADDR_CID_ANY)
                a.svm_len = __uint8_t(MemoryLayout<sockaddr_vm>.size)
                return a
            }()
            
            let socketPtr = try withUnsafeBytes(of: addr) { ptr in
                let addrPtr = ptr.assumingMemoryBound(to: sockaddr.self)
                guard let baseAddress = addrPtr.baseAddress else {
                    throw WHError("Memory read failure.")
                }
                
                return baseAddress
            }
            
            var result = Darwin.bind(fd, socketPtr, socklen_t(MemoryLayout<sockaddr_vm>.size))
            guard result == 0 else { throw SocketError(code: errno, api: "bind") }
            
            result = Darwin.listen(fd, 1024)
            guard result == 0 else { throw SocketError(code: errno, api: "listen") }
            
            logger.debug("Sending activation event, waiting for client...")
            
            eventContinuation.yield(.activated)

            onQueueWaitForConnection(fd)
        } catch {
            logger.error("\(error, privacy: .public)")
            
            eventContinuation.finish(throwing: error)
        }
    }
    
    private var connectionWaitWorkItem: DispatchWorkItem?
    
    /// Waits until a client connection comes in, then activates it and produces the appropriate events when
    /// the connection is established or cancelled.
    /// If the connection fails, waits for a bit then attempts to get a client connection again, and so on,
    /// at least until the listener itself is invalidated.
    private func onQueueWaitForConnection(_ fd: Int32) {
        guard isValid else {
            logger.debug("Skipping wait: invalidated")
            return
        }
        
        connectionWaitWorkItem?.cancel()
        connectionWaitWorkItem = nil
        
        do {
            let client = try onQueueRunAccept(fd)
            
            guard isValid else {
                logger.debug("Skipping connection: invalidated")
                return
            }
            
            self.connection = client
            
            eventContinuation.yield(.connected(client))
            
            client.activate()
        } catch {
            eventContinuation.yield(.disconnected)
            
            let waitAgainWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.connectionWaitWorkItem?.isCancelled == false else { return }
                self.onQueueWaitForConnection(fd)
            }

            self.connectionWaitWorkItem = waitAgainWorkItem

            queue.asyncAfter(deadline: .now() + 1, execute: waitAgainWorkItem)
        }
    }
    
    /// Runs the socket `accept` function on the listener file descriptor, instantiating a corresponding `Connection`
    /// instance representing the remote client once a connection has been established.
    private func onQueueRunAccept(_ fd: Int32) throws -> Connection {
        var clientAddress = sockaddr()
        var clientLength = socklen_t(MemoryLayout<sockaddr>.size)
        let clientDescriptor = Darwin.accept(fd, &clientAddress, &clientLength)
        
        logger.debug("Received client with fd \(clientDescriptor, privacy: .public)")
        
        guard clientDescriptor > 0 else { throw WHError("Client fd returned \(clientDescriptor)") }
        
        let connection = Connection(serverPort: self.port, clientDescriptor: clientDescriptor) { [weak self] error in
            guard let self else { return }
            
            guard self.isValid else {
                self.eventContinuation.yield(.disconnected)
                return
            }
            
            if self.isValid, let error {
                self.logger.warning("Connection closed: \(error, privacy: .public)")
            } else {
                self.logger.notice("Connection closed: \(self.connection?.description ?? "<nil>", privacy: .public)")
            }
            
            self.queue.async {
                self.connection = nil

                self.eventContinuation.yield(.disconnected)

                self.onQueueWaitForConnection(fd)
            }
        }
        
        logger.debug("Engaged: \(connection, privacy: .public)")
        
        return connection
    }
    
}

// MARK: - Helpers

extension WHSocket.Connection {
    var description: String { id }
}

extension WHSocket.Event {
    var description: String {
        switch self {
        case .activated:
            return "Activated"
        case .invalidated:
            return "Invalidated"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        }
    }
}
