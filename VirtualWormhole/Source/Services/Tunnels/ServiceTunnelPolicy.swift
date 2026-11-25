import Darwin
import Foundation

/// What the organization managing the host allows service tunnels to do.
///
/// The policy is only ever applied by the host. The guest has no say in it and isn't told what it contains.
public struct ServiceTunnelPolicy: Equatable, Sendable {
    /// Why a tunnel can't be used under the policy.
    public enum Restriction: Equatable, Sendable {
        case tunnels
        /// Tunnels that let the virtual machine reach a service on the host.
        case hostServices
        /// Tunnels that let the host reach a service in the virtual machine.
        case guestServices
        case unixSockets
        case tcpPorts
        case hostPort(UInt16)
        case hostSocketPath(String)

        public var explanation: String {
            switch self {
            case .tunnels: "Service tunnels are disabled by your organization."
            case .hostServices: "Your organization doesn't allow virtual machines to reach services on this Mac."
            case .guestServices: "Your organization doesn't allow this Mac to reach services in virtual machines."
            case .unixSockets: "Your organization doesn't allow service tunnels to use Unix sockets."
            case .tcpPorts: "Your organization doesn't allow service tunnels to use TCP ports."
            case .hostPort(let port): "Your organization doesn't allow service tunnels to use port \(port) on this Mac."
            case .hostSocketPath(let path): "Your organization doesn't allow service tunnels to use \(path) on this Mac."
            }
        }
    }

    /// A socket path the organization named, or a folder whose entire contents it named.
    struct SocketPathPattern: Equatable, Sendable {
        /// With links resolved, so that a path can't get around the pattern by another name for the same place.
        var path: String
        var includesContents: Bool

        static let everything = Self(path: "/", includesContents: true)

        /// - Parameter home: What `~` stands for, which lets one profile name a location in every user's home folder.
        init?(_ entry: String, home: String) {
            var entry = entry
            if entry == "~" || entry.hasPrefix("~/") { entry = home + entry.dropFirst() }
            guard entry.hasPrefix("/") else { return nil }
            includesContents = entry.hasSuffix("/")
            while entry.count > 1, entry.hasSuffix("/") { entry.removeLast() }
            path = resolvingLinks(inSocketPath: entry)
        }

        private init(path: String, includesContents: Bool) {
            self.path = path
            self.includesContents = includesContents
        }

        func matches(_ resolvedPath: String) -> Bool {
            guard includesContents else { return resolvedPath == path }
            return path == "/" || resolvedPath == path || resolvedPath.hasPrefix(path + "/")
        }
    }

    public var tunnelsDisabled = false
    public var hostServicesDisabled = false
    public var guestServicesDisabled = false
    public var unixSocketsDisabled = false
    public var tcpPortsDisabled = false
    /// Whether virtual machines are kept from asking for tunnels. Tunnels set up on the host are unaffected.
    public var requestsDisabled = false

    /// When there's a list, only these ports on the host can be used.
    private(set) var allowedHostPorts: [ClosedRange<UInt16>]?
    private(set) var deniedHostPorts: [ClosedRange<UInt16>] = []
    /// When there's a list, only these socket paths on the host can be used.
    private(set) var allowedHostSocketPaths: [SocketPathPattern]?
    private(set) var deniedHostSocketPaths: [SocketPathPattern] = []

    public static let unrestricted = ServiceTunnelPolicy()

    public init() { }

    /// Each list entry is a port ("8080") or a range of ports ("8000-8099"). An entry that can't be understood
    /// allows nothing in a list of allowed ports and denies every port in a list of denied ones, so that
    /// a mistake in a profile never permits more than the profile's author could have meant.
    public mutating func setHostPorts(allowed: [String]?, denied: [String]) {
        allowedHostPorts = allowed?.compactMap(Self.portRange)
        deniedHostPorts = denied.map { Self.portRange($0) ?? 1...UInt16.max }
    }

    /// Each list entry is the path of a socket, or of a folder followed by a slash for everything inside it.
    /// `~` stands for the home folder. Entries that can't be understood are handled as in ``setHostPorts(allowed:denied:)``.
    public mutating func setHostSocketPaths(allowed: [String]?, denied: [String], home: String = NSHomeDirectory()) {
        allowedHostSocketPaths = allowed?.compactMap { SocketPathPattern($0, home: home) }
        deniedHostSocketPaths = denied.map { SocketPathPattern($0, home: home) ?? .everything }
    }

    static func portRange(_ entry: String) -> ClosedRange<UInt16>? {
        let bounds = entry.split(separator: "-", omittingEmptySubsequences: false).map { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        switch bounds.count {
        case 1:
            guard let port = bounds[0], port > 0 else { return nil }
            return port...port
        case 2:
            guard let first = bounds[0], let last = bounds[1], first > 0, first <= last else { return nil }
            return first...last
        default:
            return nil
        }
    }

    public func permits(_ tunnel: ServiceTunnel) -> Bool { restriction(on: tunnel) == nil }

    /// The first reason the tunnel can't be used, from the broadest restriction to the most specific.
    public func restriction(on tunnel: ServiceTunnel) -> Restriction? {
        if tunnelsDisabled { return .tunnels }
        if hostServicesDisabled, !tunnel.listensOnHost { return .hostServices }
        if guestServicesDisabled, tunnel.listensOnHost { return .guestServices }

        // The organization decides what kinds of endpoints tunnels have, whichever side they're on.
        for endpoint in [tunnel.listener, tunnel.destination] {
            switch endpoint {
            case .unix: if unixSocketsDisabled { return .unixSockets }
            case .tcp, .tcp6: if tcpPortsDisabled { return .tcpPorts }
            }
        }

        // The lists are about the host's own ports and files. What a tunnel uses inside the virtual machine isn't the host's to restrict.
        switch tunnel.listensOnHost ? tunnel.listener : tunnel.destination {
        case .tcp(let port), .tcp6(let port):
            let isAllowed = allowedHostPorts?.contains { $0.contains(port) } ?? true
            if !isAllowed || deniedHostPorts.contains(where: { $0.contains(port) }) { return .hostPort(port) }
        case .unix(let path):
            let resolved = resolvingLinks(inSocketPath: path)
            let isAllowed = allowedHostSocketPaths?.contains { $0.matches(resolved) } ?? true
            if !isAllowed || deniedHostSocketPaths.contains(where: { $0.matches(resolved) }) { return .hostSocketPath(path) }
        }
        return nil
    }
}

/// Where the path leads once the links in the part of it that exists are followed.
/// A socket that hasn't been created yet is still found by the real location of its folder.
func resolvingLinks(inSocketPath path: String) -> String {
    var existing = path
    var missing = [String]()
    while true {
        if let resolved = realpath(existing, nil) {
            defer { free(resolved) }
            let base = String(cString: resolved)
            guard !missing.isEmpty else { return base }
            return (base == "/" ? "" : base) + "/" + missing.reversed().joined(separator: "/")
        }
        guard existing != "/", !existing.isEmpty else { return path }
        missing.append((existing as NSString).lastPathComponent)
        existing = (existing as NSString).deletingLastPathComponent
    }
}
