import Foundation
import UniformTypeIdentifiers

public extension UTType {
    static let virtualBuddySavedState = UTType(
        exportedAs: "codes.rambo.VirtualBuddy.SavedState",
        conformingTo: .bundle
    )
}

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
    init(packageURL: URL) throws {
        let metadataURL = VMLibraryController.savedStateInfoFileURL(in: packageURL)
        try self.init(metadataURL: metadataURL)
    }

    init(metadataURL: URL) throws {
        let data = try Data(contentsOf: metadataURL)
        self = try PropertyListDecoder.virtualBuddy.decode(Self.self, from: data)
    }

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
    func createSavedStatePackage(in library: VMLibraryController) throws -> URL {
        try library.createSavedStatePackage(for: self)
    }

    /// Convenience for ``VMLibraryController/savedStateDataFileURL(in:)``.
    nonisolated func savedStateDataFileURL(in packageURL: URL) -> URL {
        VMLibraryController.savedStateDataFileURL(in: packageURL)
    }

    /// Convenience for ``VMLibraryController/savedStateInfoFileURL(in:)``.
    nonisolated func savedStateInfoFileURL(in packageURL: URL) -> URL {
        VMLibraryController.savedStateInfoFileURL(in: packageURL)
    }
}

@MainActor
public extension VMLibraryController {

    func savedStatesLibraryURL() throws -> URL {
        let url = self.libraryURL.appending(path: "_SavedState", directoryHint: .isDirectory)
        return try url.creatingDirectoryIfNeeded()
    }

    func savedStateDirectoryURL(for model: VBVirtualMachine) throws -> URL {
        try model.savedStatesDirectoryURL(in: self)
    }

    func createSavedStatePackage(for model: VBVirtualMachine) throws -> URL {
        let baseURL = try savedStateDirectoryURL(for: model)

        let suffix = DateFormatter.savedStateFileName.string(from: .now)
        let url = baseURL.appendingPathComponent("Save-\(suffix)", conformingTo: .virtualBuddySavedState)
        return try url.creatingDirectoryIfNeeded()
    }

    nonisolated static func savedStateDataFileURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent("State.vzvmsave")
    }

    nonisolated static func savedStateInfoFileURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent("Info", conformingTo: .propertyList)
    }

    func virtualMachine(with uuid: UUID) throws -> VBVirtualMachine {
        guard let model = virtualMachines.first(where: { $0.metadata.uuid == uuid }) else {
            throw Failure("Virtual machine not found with UUID \(uuid)")
        }
        return model
    }

    func virtualMachineURL(forSavedStatePackageURL url: URL) throws -> URL {
        try virtualMachine(forSavedStatePackageURL: url).bundleURL
    }

    func virtualMachine(forSavedStatePackageURL url: URL) throws -> VBVirtualMachine {
        let metadata = try VBSavedStateMetadata(packageURL: url)
        let model = try virtualMachine(forSavedStateMetadata: metadata)
        return model
    }

    func virtualMachine(forSavedStateMetadata metadata: VBSavedStateMetadata) throws -> VBVirtualMachine {
        try virtualMachine(with: metadata.vmUUID)
    }
}

private extension DateFormatter {
    static let savedStateFileName: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd_HH;mm;ss"
        return f
    }()
}
