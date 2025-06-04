import Foundation
import BuddyFoundation

public struct LegacyCatalog: Decodable {
    public let channels: [LegacyCatalogChannel]
    public let groups: [LegacyCatalogGroup]
    public let images: [LegacyRestoreImage]
}

public struct LegacyCatalogChannel: Hashable, Identifiable, Codable {
    public struct Authentication: Hashable, Identifiable, Codable {
        public var id: String { name }
        public var name: String
        public var url: URL
        public var note: String
    }

    public var id: String
    public var name: String
    public var note: String
    public var icon: String
}

public struct LegacyCatalogGroup: Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var majorVersion: SoftwareVersion
    public var minHostVersion: SoftwareVersion
}

public struct LegacyRestoreImage: Hashable, Identifiable, Codable {
    public var id: String { build }
    public var group: LegacyCatalogGroup
    public var channel: LegacyCatalogChannel
    public var name: String
    public var build: String
    public var url: URL
    public var needsCookie: Bool?
}

public extension LegacyCatalog {
    private static let decoder = JSONDecoder()

    init(data: Data) throws {
        self = try Self.decoder.decode(Self.self, from: data)
    }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }
}
