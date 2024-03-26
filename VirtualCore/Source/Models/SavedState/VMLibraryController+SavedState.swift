import Foundation

@MainActor
public extension VMLibraryController {

    nonisolated static let savedStateDirectoryName = "_SavedState"

    func savedStatesLibraryURL() throws -> URL {
        let url = self.libraryURL.appending(path: Self.savedStateDirectoryName, directoryHint: .isDirectory)
        return try url.creatingDirectoryIfNeeded()
    }

    func savedStateDirectoryURL(for model: VBVirtualMachine) throws -> URL {
        try model.savedStatesDirectoryURL(in: self)
    }

    func createSavedStatePackage(for model: VBVirtualMachine) throws -> VBSavedStatePackage {
        let baseURL = try savedStateDirectoryURL(for: model)

        return try VBSavedStatePackage(creatingPackageInDirectoryAt: baseURL, model: model)
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
        let package = try VBSavedStatePackage(url: url)
        let model = try virtualMachine(forSavedStateMetadata: package.metadata)
        return model
    }

    func virtualMachine(forSavedStateMetadata metadata: VBSavedStateMetadata) throws -> VBVirtualMachine {
        try virtualMachine(with: metadata.vmUUID)
    }
}
