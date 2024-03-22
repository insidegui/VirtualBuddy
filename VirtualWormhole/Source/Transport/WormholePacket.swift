import Foundation

struct WormholePacket: Codable {
    var payloadType: String
    var payload: Data
}

extension WormholePacket {

    init<T: Codable>(_ payload: T) throws {
        let data = try PropertyListEncoder.wormhole.encode(payload)
        let typeName = String(describing: type(of: payload))

        self.init(payloadType: typeName, payload: data)
    }

    func encoded() throws -> Data {
        try PropertyListEncoder.wormhole.encode(self)
    }

    static func decode(from data: Data) throws -> WormholePacket {
        try PropertyListDecoder.wormhole.decode(WormholePacket.self, from: data)
    }
    
}

extension PropertyListEncoder {
    static let wormhole: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
}

extension PropertyListDecoder {
    static let wormhole = PropertyListDecoder()
}
