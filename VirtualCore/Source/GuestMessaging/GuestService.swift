import Foundation
import VirtualMessagingTransport
import VirtualMessagingService
import OSLog

/// Base class for guest services.
/// - warning: The current implementation supports only a single client per service.
open class GuestService: @unchecked Sendable {
    public init() { }
    
    /// Unique identifier for the service.
    open var id: String { preconditionFailure("Subclasses must implement \(#function)") }

    private var isListener = false
    private var _sending: VMMessageSending?
    private var _router: MessageRouter?

    public var sending: VMMessageSending {
        get throws(VMServiceConnectionError) {
            try _sending.require(VMServiceConnectionError.notConnected)
        }
    }

    public var router: MessageRouter {
        get throws(VMServiceConnectionError) {
            try _router.require(VMServiceConnectionError.notConnected)
        }
    }

    /// Called by the service instance when the connection becomes available.
    /// The service may then register payload types with the router.
    func activate(connection: VMServiceConnection, router: MessageRouter) async throws {
        isListener = connection.isListener

        if !connection.isListener {
            /// For clients, our `send` method will send on the main service connection.
            /// For services, this will be set to the peer connection when a client connects.
            /// Only one client per service is supported at this time.
            _sending = connection
        }

        _router = router

        bootstrapCompleted()
    }
    
    /// Subclasses may override to perform initialization steps after the service has been successfully activated,
    /// but before ``connected(_:)`` is invoked.
    open func bootstrapCompleted() { }

    /// Called by the service instance when the service is connected to the remote peer.
    open func connected(_ connection: VMPeerConnection) {
        if isListener {
            _sending = connection
        }
    }

    /// Called by the service instance when the service is disconnected from the remote peer.
    open func disconnected(_ connection: VMPeerConnection) {
        if isListener {
            _sending = nil
        }
    }
    
    /// Register a receiver for a given message payload type.
    /// - Parameters:
    ///   - payloadType: The payload type.
    ///   - closure: The receiver closure, which receives the decoded payload and the connection that sent the payload.
    ///
    /// Use this method to register message handlers specific to your service implementation.
    ///
    /// - note: It is an error to call this method before ``activate(connection:router:)`` has been called. Doing so results in an assertion failure.
    public func receive<P: RoutableMessagePayload>(_ payloadType: P.Type, using closure: @Sendable @escaping (_ payload: P, _ connection: VMPeerConnection) async throws -> Void) {
        do {
            try router.registerHandler(for: payloadType, context: VMPeerConnection.self, using: closure)
        } catch {
            assertionFailure("Attempt to register message handler before activation. \(error)")
        }
    }

    /// Register a receiver for a given message payload type.
    /// - Parameters:
    ///   - closure: The receiver closure, which receives the decoded payload and the connection that sent the payload.
    ///
    /// Use this method to register message handlers specific to your service implementation.
    ///
    /// - note: It is an error to call this method before ``activate(connection:router:)`` has been called. Doing so results in an assertion failure.
    public func register<P: RoutableMessagePayload>(_ handler: @Sendable @escaping (_ payload: P, _ connection: VMPeerConnection) async throws -> Void) {
        do {
            try router.registerHandler(for: P.self, context: VMPeerConnection.self, using: handler)
        } catch {
            assertionFailure("Attempt to register message handler before activation. \(error)")
        }
    }

    /// Sends a payload to the other side of the connection.
    /// - Parameter payload: The payload to be sent.
    ///
    /// Use this method to send messages to the remote peer.
    public func send(_ payload: some RoutableMessagePayload) async throws {
        try await sending.send(payload)
    }
    
    /// Sends a payload to the other side of the connection, expecting a response back.
    /// - Parameter payload: The payload to be sent.
    /// - Returns: The response from the other side of the connection.
    ///
    /// Use this method to send messages to the remote peer when the remote peer is always expected to send a specific payload type back
    /// as a response to the message it receives.
    ///
    /// - note: There's currently no timeout mechanism implemented, so if the remote peer doesn't respond with the expected message type, this method will never return.
    public func sendWithReply<R: RoutableMessagePayload>(_ payload: some RoutableMessagePayload) async throws(VMServiceConnectionError) -> R {
        let router = try self.router

        let responseTask = Task {
            await withCheckedContinuation { continuation in
                router.onNext(R.self, context: VMPeerConnection.self) { response, _ in
                    continuation.resume(returning: response)
                }
            }
        }

        try await sending.send(payload)

        return await responseTask.value
    }
}

/// Represents a live instance of a ``GuestService``.
final class GuestServiceInstance: Sendable {
    let id: String
    let router: MessageRouter
    let service: GuestService
    private let logger: Logger

    init<S: GuestService>(service: S) {
        self.id = service.id
        self.logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "GuestServiceInstance(\(id.shortServiceID))")
        self.router = MessageRouter(label: id.shortServiceID)
        self.service = service
    }

    func activate(channelProvider: VMChannelProvider) async throws {
        let connection = VMServiceConnection(id: id, isListener: true)

        try await connection.activate(with: channelProvider) { [weak self] peer in
            guard let self else { return }
            service.connected(peer)
        } invalidationHandler: { [weak self] peer in
            guard let self else { return }
            service.disconnected(peer)
        } messageHandler: { [weak self] message in
            guard let self else { return }
            do {
                try await router.handle(message: message.content, context: message.connection)
            } catch {
                logger.error("Message handler failure. \(error, privacy: .public)")
            }
        }

        try await service.activate(connection: connection, router: router)
    }
}

public extension String {
    var shortServiceID: String { split(separator: ".").last.flatMap(String.init) ?? self }
}

public extension GuestService {
    var shortID: String { id.shortServiceID }
}
