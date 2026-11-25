import Foundation

public enum TunnelEndpoint: Codable, Hashable, Sendable {
    case tcp(UInt16)
    case tcp6(UInt16)
    case unix(String)

    public var address: String {
        switch self {
        case .tcp(let port): return "127.0.0.1:\(port)"
        case .tcp6(let port): return "[::1]:\(port)"
        case .unix(let path): return path
        }
    }

    public var isValid: Bool {
        switch self {
        case .tcp(let port), .tcp6(let port): return port > 0
        case .unix(let path):
            return path.hasPrefix("/") && !path.hasSuffix("/") &&
                path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) &&
                !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.isBidiControl })
        }
    }
}

public struct ServiceTunnel: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var isEnabled = true
    public let listensOnHost: Bool
    public let listener: TunnelEndpoint
    public let destination: TunnelEndpoint

    public init(listensOnHost: Bool, listener: TunnelEndpoint, destination: TunnelEndpoint) {
        self.id = UUID()
        self.listensOnHost = listensOnHost
        self.listener = listener
        self.destination = destination
    }

    public var description: String {
        let source = listensOnHost ? "Host Mac" : "Guest VM"
        let target = listensOnHost ? "Guest VM" : "Host Mac"
        return "\(source)  \(listener.address) → \(target)  \(destination.address)"
    }

    public func canAdd(to rules: [Self]) -> Bool {
        rules.count < 32 && listener.isValid && destination.isValid && !rules.contains {
            $0.id == id || ($0.listensOnHost == listensOnHost && $0.listener == listener)
        }
    }
}
