import Foundation

public struct VBSavedStateMetadata: Identifiable, Hashable, Codable {
    public var id: UUID
    public var vmUUID: UUID
    public var date: Date
    public var appVersion: SoftwareVersion
    public var appBuild: Int
    public var hostECID: UInt64?
}

// MARK: - Saved State Metadata Creation

public extension VBSavedStateMetadata {
    init(model: VBVirtualMachine) {
        let ecid = ProcessInfo.processInfo.machineECID
        
        assert(ecid != nil, "Failed to get host machine ECID")

        self.init(
            id: UUID(),
            vmUUID: model.metadata.uuid,
            date: .now,
            appVersion: Bundle.main.vbVersion,
            appBuild: Bundle.main.vbBuild,
            hostECID: ecid
        )
    }
}

// MARK: - Directory Helpers

@MainActor
public extension VBVirtualMachine {
    func savedStatesDirectoryURL(in library: VMLibraryController) throws -> URL {
        let baseURL = try library.savedStatesLibraryURL()
        
        return try baseURL
            .appending(path: metadata.uuid.uuidString, directoryHint: .isDirectory)
            .creatingDirectoryIfNeeded()
    }

    /// Convenience for ``VMLibraryController/createSavedStatePackage(for:)``.
    func createSavedStatePackage(in library: VMLibraryController) throws -> VBSavedStatePackage {
        try library.createSavedStatePackage(for: self)
    }
}
