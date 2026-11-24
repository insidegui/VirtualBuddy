import Foundation

public struct MacDebugError: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct DebugLaunchOptions: Codable, Sendable {
    public let arguments: [String]
    public let environment: [String: String]
    public init(arguments: [String], environment: [String: String]) {
        self.arguments = arguments
        self.environment = environment
    }
}

public struct DebugSystemImages: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let name: String
        public let bytes: Int64

        public init(name: String, bytes: Int64) {
            self.name = name
            self.bytes = bytes
        }
    }
    public let version: String
    public let build: String
    public let architecture: String
    public let uuid: UUID
    public let files: [File]
    public var primary: String { "dyld_shared_cache_\(architecture)" }

    public init(version: String, build: String, architecture: String, uuid: UUID, files: [File]) {
        self.version = version
        self.build = build
        self.architecture = architecture
        self.uuid = uuid
        self.files = files
    }

    public func validate() throws {
        let digits = CharacterSet(charactersIn: "0123456789.")
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        func valid(_ value: String, _ allowed: CharacterSet) -> Bool {
            (1...100).contains(value.utf8.count) && value.unicodeScalars.allSatisfy(allowed.contains)
        }
        guard valid(version, digits), valid(build, letters), ["arm64", "arm64e"].contains(architecture),
              Set(files.map(\.name)).count == files.count, files.count < 256,
              files.contains(where: { $0.name == primary }), files.contains(where: { $0.name == "dyld" }),
              files.allSatisfy({ file in
                  file.bytes > 0 && file.bytes <= 32 << 30 && (file.name == "dyld" || file.name == primary ||
                    (file.name.hasPrefix(primary + ".") && valid(String(file.name.dropFirst(primary.count + 1)), letters.union(digits))))
              }) else { throw MacDebugError("The target reported an invalid system image set.") }
    }
}
