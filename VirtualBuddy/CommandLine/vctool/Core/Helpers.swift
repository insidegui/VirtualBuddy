import Foundation
import ArgumentParser
import BuddyFoundation

extension URL {
    init(validating string: String) throws {
        guard let url = URL(string: string) else {
            throw "Invalid URL: \"\(string)\""
        }
        self = url
    }
}

extension ProcessInfo {
    nonisolated(unsafe) private static var _sessionID: String?

    var sessionID: String {
        if let id = Self._sessionID { return id }

        let newID = UUID().uuidString

        Self._sessionID = newID

        return newID
    }
}

extension URL {
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var isExistingDirectory: Bool {
        var isDir = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    func ensureExistingFile() throws -> URL {
        try requireExistingFile()
        return self
    }

    func ensureExistingDirectory(createIfNeeded: Bool = false) throws -> URL {
        try requireExistingDirectory(createIfNeeded: createIfNeeded)
        return self
    }

    func requireExistingFile() throws {
        guard exists else {
            throw "File doesn't exist at \(path)"
        }
        guard !isExistingDirectory else {
            throw "Expected a file, but found a directory at \(path)"
        }
    }

    func requireExistingDirectory(createIfNeeded: Bool = false) throws {
        if exists {
            guard isExistingDirectory else {
                throw "Expected a directory, but found a regular file at \(path)"
            }
        } else {
            guard createIfNeeded else {
                throw "Directory doesn't exist at \(path)"
            }

            try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        }
    }

    static var baseTempURL: URL {
        get throws {
            let tempBase = FileManager.default.temporaryDirectory
            let sessionBase = tempBase.appendingPathComponent(ProcessInfo.processInfo.sessionID)
            if !FileManager.default.fileExists(atPath: sessionBase.path) {
                try FileManager.default.createDirectory(at: sessionBase, withIntermediateDirectories: true)
            }
            return sessionBase
        }
    }

    static func tempFileURL(name: String, create: Bool = false) throws -> URL {
        let fileURL = try baseTempURL.appendingPathComponent(name)
        if create, !fileURL.exists {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        return fileURL
    }

    static func tempDirURL(name: String, create: Bool = false) throws -> URL {
        let dirURL = try baseTempURL.appendingPathComponent(name)
        if create, !dirURL.exists {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        return dirURL
    }

    static var vctoolCache: URL {
        get throws {
            try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "vctool", directoryHint: .isDirectory)
        }
    }        
}

extension String {
    var resolvedPath: String { (self as NSString).expandingTildeInPath }
    var resolvedURL: URL { URL(filePath: resolvedPath) }
}

extension CatalogGuestPlatform: EnumerableFlag { }

extension ResolvedFeatureStatus {
    var cliDescription: String {
        switch self {
        case .supported:
            return "✅ Supported"
        case .warning(let message):
            return "⚠️ Warning: \(message)"
        case .unsupported(let message):
            return "🛑 Not Supported: \(message)"
        }
    }
}

extension SoftwareVersion: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(string: argument)
    }
}

extension RequirementSet {
    func matches(info: BuildInfo) -> Bool {
        guard let manifestMinVersionHost = info.virtualMachineMinHostOS else { return true }
        guard manifestMinVersionHost == self.minVersionHost else { return false }

        guard let manifestMinMemory = info.virtualMachineMinMemorySizeMB else { return true }
        guard manifestMinMemory == self.minMemorySizeMB else { return false }

        guard let manifestMinCPU = info.virtualMachineMinCPUCount else { return true }
        return manifestMinCPU == self.minCPUCount
    }
}

extension BuildInfo {
    var requirementsDescription: String {
        let minVer = virtualMachineMinHostOS?.description ?? "?"
        let minMem = virtualMachineMinMemorySizeMB.flatMap({ String($0) }) ?? "?"
        let minCPU = virtualMachineMinCPUCount.flatMap({ String($0) }) ?? "?"
        return "minHostVersion: \(minVer) | minMemory: \(minMem) | minCPU: \(minCPU)"
    }
}

extension RestoreImage: TreeStringConvertible, CustomStringConvertible {
    public var description: String { description(level: 0) }
}
