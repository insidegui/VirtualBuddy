import Foundation

public struct SoftwareVersion: Hashable, CustomStringConvertible, Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public static let empty = SoftwareVersion(major: 0, minor: 0, patch: 0)
}

public extension SoftwareVersion {

    init?(string: String) {
        let components = string.components(separatedBy: ".")

        guard !components.isEmpty else { return nil }
        guard let major = Int(components[0]) else { return nil }

        self.major = major

        if components.count > 1 {
            self.minor = Int(components[1]) ?? 0
        } else {
            self.minor = 0
        }

        if components.count > 2 {
            self.patch = Int(components[2]) ?? 0
        } else {
            self.patch = 0
        }
    }

}

extension SoftwareVersion {
    public var description: String { stringRepresentation }
    private var stringRepresentation: String { String(format: "%d.%d.%d", major, minor, patch) }
}

public extension SoftwareVersion {

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        guard let vers = SoftwareVersion(string: str) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid app version string"))
        }
        self = vers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringRepresentation)
    }

}

public extension SoftwareVersion {

    static func >(lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        if lhs.major == rhs.major {
            if lhs.minor == rhs.minor {
                return lhs.patch > rhs.patch
            }

            return lhs.minor > rhs.minor
        } else {
            return lhs.major > rhs.major
        }
    }

    static func <(lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        if lhs.major == rhs.major {
            if lhs.minor == rhs.minor {
                return lhs.patch < rhs.patch
            }

            return lhs.minor < rhs.minor
        } else {
            return lhs.major < rhs.major
        }
    }

    static func >=(lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        if lhs.major == rhs.major {
            if lhs.minor == rhs.minor {
                return lhs.patch >= rhs.patch
            }

            return lhs.minor >= rhs.minor
        } else {
            return lhs.major >= rhs.major
        }
    }

    static func <=(lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        if lhs.major == rhs.major {
            if lhs.minor == rhs.minor {
                return lhs.patch <= rhs.patch
            }

            return lhs.minor <= rhs.minor
        } else {
            return lhs.major <= rhs.major
        }
    }

}
