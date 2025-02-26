import Foundation

@MainActor
public extension VMLibraryController {

    nonisolated static let savedStateDirectoryName = "_SavedState"

    var savedStatesDirectoryURL: URL {
        self.libraryURL.appending(path: Self.savedStateDirectoryName, directoryHint: .isDirectory)
    }

    func savedStatesLibraryURLCreatingIfNeeded() throws -> URL {
        try savedStatesDirectoryURL.creatingDirectoryIfNeeded()
    }

    func savedStateDirectoryURL(for model: VBVirtualMachine) -> URL {
        savedStatesDirectoryURL
            .appending(path: model.metadata.uuid.uuidString, directoryHint: .isDirectory)
    }

    func savedStateDirectoryURLCreatingIfNeeded(for model: VBVirtualMachine) throws -> URL {
        try savedStateDirectoryURL(for: model)
            .creatingDirectoryIfNeeded()
    }

    func createSavedStatePackage(for model: VBVirtualMachine, snapshotName name: String) throws -> VBSavedStatePackage {
        let baseURL = try model.savedStatesDirectoryURLCreatingIfNeeded(in: self)

        return try VBSavedStatePackage(creatingPackageInDirectoryAt: baseURL, model: model, snapshotName: name)
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
        let metadata = try VBSavedStateMetadata(packageAt: url)
        let model = try virtualMachine(forSavedStateMetadata: metadata)
        return model
    }

    func virtualMachine(forSavedStateMetadata metadata: VBSavedStateMetadata) throws -> VBVirtualMachine {
        try virtualMachine(with: metadata.vmUUID)
    }
}
