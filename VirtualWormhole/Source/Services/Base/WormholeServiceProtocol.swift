import Foundation
import Virtualization
import OSLog

/// Manages multiple connections between the current machine and its remote peers.
/// Provides facilities for `WormholeService` to transmit packets between the local host and multiple peers.
public protocol WormholeConnectionProvider: AnyObject {

    /// Sends payload to peer.
    func send<T: WHPayload>(_ payload: T) async

    /// Streams payloads of the specified type sent from remote peers to the local host.
    func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncStream<T>

}

/// Represents a single remote connection to the current machine, be it a guest to host connection or vice-versa.
/// There's only ever a single service instance for each active `WormholeService` type, but each
/// service might be talking to multiple `WormholeConnection` instances, one per remote peer.
public protocol WormholeConnection: AnyObject {

    var side: WHConnectionSide { get }

    var remotePeerID: WHPeerID { get }

    func send<T: WHPayload>(_ payload: T) async

    func stream<T: WHPayload>(for payloadType: T.Type) -> AsyncThrowingStream<T, Error>

}

public protocol WormholeService: AnyObject {

    static var port: WHServicePort { get }

    static var id: String { get }
    
    init(provider: WormholeConnectionProvider)
    
    func activate()
    
}
