import Foundation

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
    public var failureReason: String? { self }
}

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
}

extension String {
    var resolvedPath: String { (self as NSString).expandingTildeInPath }
    var resolvedURL: URL { URL(filePath: resolvedPath) }
}