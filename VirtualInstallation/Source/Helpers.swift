import Foundation

extension URL {
    var safePath: String { absoluteURL.path(percentEncoded: false) }

    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var isExistingDirectory: Bool {
        var isDir = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    func ensureExistingDirectory(createIfNeeded: Bool = false) throws -> URL {
        if !exists {
            guard createIfNeeded else {
                throw CocoaError(.fileNoSuchFile)
            }

            try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        }
        try requireExistingDirectory()
        return self
    }

    func requireExistingDirectory() throws {
        guard exists else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard isExistingDirectory else {
            throw CocoaError(.fileReadInvalidFileName)
        }
    }

    static var viApplicationSupportURL: URL {
        do {
            let url: URL

            url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: Bundle.main.bundleURL.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)

            return try url.ensureExistingDirectory(createIfNeeded: true)
        } catch {
            assertionFailure("Failed to create application support directory: \(error)")
            return URL(filePath: NSTemporaryDirectory())
        }
    }
}

extension PropertyListEncoder {
    static let xpc: PropertyListEncoder = {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return e
    }()
}

extension PropertyListDecoder {
    static let xpc = PropertyListDecoder()
}

private final class _VILookupClass { }
extension Bundle {
    static let virtualInstallation = Bundle(for: _VILookupClass.self)
}

extension ProcessInfo {
    #if DEBUG
    /// When `VI_TEST_MODE` is set to `1` in the environment, installation uses the test backend instead of attempting to restore a real device.
    static let virtualInstallationTestModeEnabled: Bool = processInfo.environment["VI_TEST_MODE"] == "1"
    #else
    /// Test mode always disabled in release builds.
    static let virtualInstallationTestModeEnabled = false
    #endif
}

extension AMRestorableDeviceState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .DFU: return "DFU"
        case .recovery: return "Recovery"
        case .restoreOS: return "RestoreOS"
        case .bootedOS: return "BootedOS"
        @unknown default: return "Unknown(\(rawValue))"
        }
    }
}
