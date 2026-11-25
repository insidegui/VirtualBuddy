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

    /// A socket path is only valid in the one spelling that reads as the location it names,
    /// because the host user approves a tunnel by reading its path.
    public var isValid: Bool {
        switch self {
        case .tcp(let port), .tcp6(let port): return port > 0
        case .unix(let path):
            guard path.hasPrefix("/"), path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return false }
            // Rejects a trailing or repeated slash along with the components that name another directory.
            let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." } && path.unicodeScalars.allSatisfy(\.isAllowedInSocketPath)
        }
    }

    /// Characters outside ASCII can be indistinguishable from the ones a well-known path is spelled with.
    public var hasCharactersOutsideASCII: Bool {
        guard case .unix(let path) = self else { return false }
        return !path.unicodeScalars.allSatisfy(\.isASCII)
    }
}

extension String {
    /// Text received from the other side of a tunnel, made safe to show next to a tunnel in the app.
    /// The other side chooses every character of it, so anything that could hide, reorder or
    /// break up what's displayed is removed, and its length is limited.
    var displayableTunnelText: String {
        var text = String.UnicodeScalarView()
        for scalar in unicodeScalars.prefix(1024) where scalar.isAllowedInSocketPath {
            text.append(scalar)
        }
        return String(String(text).prefix(256))
    }
}

private extension Unicode.Scalar {
    /// Excludes everything that is invisible, reorders text or breaks a line where the path is displayed.
    var isAllowedInSocketPath: Bool {
        switch properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator: false
        case .spaceSeparator: self == " "
        default: !properties.isBidiControl && !properties.isDefaultIgnorableCodePoint
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
        let source = listensOnHost ? "Host" : "Guest"
        let target = listensOnHost ? "Guest" : "Host"
        return "\(source)  \(listener.address) → \(target)  \(destination.address)"
    }

    public func canAdd(to rules: [Self]) -> Bool {
        rules.count < 32 && listener.isValid && destination.isValid && !rules.contains {
            $0.id == id || ($0.listensOnHost == listensOnHost && $0.listener == listener)
        }
    }
}
