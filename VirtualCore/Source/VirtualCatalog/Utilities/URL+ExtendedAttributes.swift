import Foundation
import BuddyFoundation

extension URL {
    func vb_encodeExtendedAttribute<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder.vb_extendedAttribute.encode(value)
        try vb_setExtendedAttributeData(data, forKey: key)
    }

    func vb_decodeExtendedAttribute<T: Decodable>(forKey key: String) -> T? {
        try? vb_extendedAttributeData(forKey: key).flatMap {
            try JSONDecoder.vb_extendedAttribute.decode(T.self, from: $0)
        }
    }

    func vb_setExtendedAttributeData(_ value: Data, forKey key: String, base64: Bool = true) throws {
        let effectiveValue = base64 ? value.base64EncodedData() : value

        let size = effectiveValue.count
        let err = effectiveValue.withUnsafeBytes { ptr in
            setxattr(path, key, ptr.baseAddress, size, 0, 0)
        }

        guard err == 0 else {
            throw "setxattr error code \(err)"
        }
    }

    func vb_extendedAttributeData(forKey key: String, base64: Bool = true) -> Data? {
        var size = getxattr(path, key, nil, .max, 0, 0)

        guard size > 0 else {
            return nil
        }

        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 2)
        size = getxattr(path, key, pointer, size, 0, 0)

        guard size > 0 else {
            pointer.deallocate()
            return nil
        }

        let data = Data(bytesNoCopy: pointer, count: size, deallocator: .free)

        guard base64 else { return data }

        return Data(base64Encoded: data)
    }

    func vb_removeExtendedAttribute(forKey key: String) throws {
        let err = removexattr(path, key, 0)
        guard err == 0 else {
            throw "removexattr error code \(err)"
        }
    }
}

private extension JSONEncoder {
    static let vb_extendedAttribute = JSONEncoder()
}
private extension JSONDecoder {
    static let vb_extendedAttribute = JSONDecoder()
}
