import Foundation
import BuddyFoundation

public struct VBSavedStateMetadata: Identifiable, Hashable, Codable {
    public var id: UUID
    public var vmUUID: UUID
    public var date: Date
    public var appVersion: SoftwareVersion
    public var appBuild: Int
    public var hostECID: UInt64?

    /// Copy of ``VBMacDevice/storageDevices`` as those existed at the time the snapshot was taken.
    /// The ``VBStorageDevice/isSavedStateClone`` property is set to `true` once the state has been saved.
    /// Only managed disk images are cloned alongside saved states, custom user-provided images are referenced from their original locations.
    @DecodableDefault.EmptyList
    public var storageDevices: [VBStorageDevice]

    init(id: UUID, vmUUID: UUID, date: Date, appVersion: SoftwareVersion, appBuild: Int, hostECID: UInt64? = nil, storageDevices: [VBStorageDevice]) {
        self.id = id
        self.vmUUID = vmUUID
        self.date = date
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.hostECID = hostECID
        self.storageDevices = storageDevices
    }
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
            hostECID: ecid,
            storageDevices: model.configuration.hardware.storageDevices // will be modified once package is saved
        )
    }
}

// MARK: - Directory Helpers

@MainActor
public extension VBVirtualMachine {
    func savedStatesDirectoryURL(in library: VMLibraryController) -> URL {
        library.savedStateDirectoryURL(for: self)
    }

    func savedStatesDirectoryURLCreatingIfNeeded(in library: VMLibraryController) throws -> URL {
        try library.savedStateDirectoryURLCreatingIfNeeded(for: self)
    }

    /// Convenience for ``VMLibraryController/createSavedStatePackage(for:)``.
    func createSavedStatePackage(in library: VMLibraryController, snapshotName name: String) throws -> VBSavedStatePackage {
        try library.createSavedStatePackage(for: self, snapshotName: name)
    }
}
