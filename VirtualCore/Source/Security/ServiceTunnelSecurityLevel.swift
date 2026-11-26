import Foundation
import VirtualWormhole

/// How much of a virtual machine's service tunnels the host user reviews before they run.
///
/// Levels are ordered from the least to the most review, so the stricter of two levels is their maximum.
public enum ServiceTunnelSecurityLevel: String, CaseIterable, Comparable, Sendable {
    /// Tunnels run as saved and guests add tunnels on their own.
    case reviewNone = "Never"
    /// A tunnel is reviewed the first time its host side is seen, and never again on this Mac.
    case reviewNew = "NewTunnels"
    /// Every tunnel a guest requests, and every record the host didn't approve itself, is reviewed.
    case reviewAll = "EveryChange"

    /// What applies whenever the saved level is missing or can't be trusted.
    public static let strictest = ServiceTunnelSecurityLevel.reviewAll

    private var rank: Int {
        switch self {
        case .reviewNone: 0
        case .reviewNew: 1
        case .reviewAll: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// What a tunnel gives access to on the host, which is all that remembering a reviewed tunnel is about.
///
/// The guest side isn't part of it: whatever a guest connects on its own end, the host exposes
/// or reaches the same thing.
public struct ServiceTunnelIdentity: Hashable, Codable, Sendable {
    public let listensOnHost: Bool
    public let hostEndpoint: TunnelEndpoint

    public init(_ tunnel: ServiceTunnel) {
        listensOnHost = tunnel.listensOnHost
        hostEndpoint = tunnel.listensOnHost ? tunnel.listener : tunnel.destination
    }
}
