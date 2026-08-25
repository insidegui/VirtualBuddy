import Foundation

public enum FileTransferProtocol {
    public static let port: UInt32 = 51_050
    public static let version = 1

    private static let maximumFrameLength = 16 * 1_024 * 1_024

    public static func writeFrame<T: Encodable>(_ value: T, to handle: FileHandle) throws {
        let data = try JSONEncoder.wormhole.encode(value)
        try writeFrame(data, to: handle)
    }

    public static func writeFrame(_ data: Data, to handle: FileHandle) throws {
        var encodedLength = UInt64(data.count).littleEndian
        let lengthData = withUnsafeBytes(of: &encodedLength) { Data($0) }
        try handle.write(contentsOf: lengthData)
        try handle.write(contentsOf: data)
    }

    public static func writeEnd(to handle: FileHandle) throws {
        var encodedLength = UInt64.zero
        try handle.write(contentsOf: withUnsafeBytes(of: &encodedLength) { Data($0) })
    }

    public static func readFrame<T: Decodable>(_ type: T.Type, from handle: FileHandle) throws -> T? {
        guard let data = try readFrame(from: handle) else { return nil }
        return try JSONDecoder.wormhole.decode(type, from: data)
    }

    public static func readFrame(from handle: FileHandle) throws -> Data? {
        let lengthData = try readExactly(MemoryLayout<UInt64>.size, from: handle)
        let length = lengthData.withUnsafeBytes { buffer in
            UInt64(littleEndian: buffer.loadUnaligned(as: UInt64.self))
        }

        guard length > 0 else { return nil }
        guard length <= maximumFrameLength else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "File transfer frame is too large: \(length) bytes."]
            )
        }

        return try readExactly(Int(length), from: handle)
    }

    public static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        guard count >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var data = Data(capacity: count)

        while data.count < count {
            try Task.checkCancellation()

            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [NSLocalizedDescriptionKey: "The file transfer connection closed before all data arrived."]
                )
            }

            data.append(chunk)
        }

        return data
    }
}

public struct FileTransferManifest: Codable, Hashable, Sendable {
    public var version: Int
    public var sessionID: UUID
    public var rootPaths: [String]

    public init(sessionID: UUID, rootPaths: [String]) {
        self.version = FileTransferProtocol.version
        self.sessionID = sessionID
        self.rootPaths = rootPaths
    }
}

public struct FileTransferEntry: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case directory
        case regularFile
        case symbolicLink
    }

    public var relativePath: String
    public var kind: Kind
    public var byteCount: UInt64
    public var posixPermissions: UInt16?
    public var modificationDate: Date?
    public var symbolicLinkDestination: String?

    public init(
        relativePath: String,
        kind: Kind,
        byteCount: UInt64 = 0,
        posixPermissions: UInt16? = nil,
        modificationDate: Date? = nil,
        symbolicLinkDestination: String? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = byteCount
        self.posixPermissions = posixPermissions
        self.modificationDate = modificationDate
        self.symbolicLinkDestination = symbolicLinkDestination
    }
}

public enum FileTransferPath {
    public static func destination(for relativePath: String, under root: URL) throws -> URL {
        guard isValid(relativePath) else {
            throw CocoaError(
                .fileReadInvalidFileName,
                userInfo: [NSLocalizedDescriptionKey: "Invalid file transfer path: \(relativePath)"]
            )
        }

        let standardizedRoot = root.standardizedFileURL
        let destination = standardizedRoot.appending(path: relativePath).standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"

        guard destination.path.hasPrefix(rootPrefix) else {
            throw CocoaError(
                .fileReadInvalidFileName,
                userInfo: [NSLocalizedDescriptionKey: "File transfer path escapes its destination: \(relativePath)"]
            )
        }

        return destination
    }

    public static func isValid(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty,
              !relativePath.contains("\0"),
              !(relativePath as NSString).isAbsolutePath
        else { return false }

        return relativePath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}
