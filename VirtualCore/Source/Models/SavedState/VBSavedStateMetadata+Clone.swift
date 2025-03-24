import Foundation

extension VBSavedStateMetadata {
    static func createStorageDeviceClones(packageURL: URL, model: VBVirtualMachine) async throws -> [VBStorageDevice] {
        let inputDevices = model.configuration.hardware.storageDevices
        var outputDevices = [VBStorageDevice]()

        for var device in inputDevices {
            guard case .managedImage = device.backing else {
                /// Custom images are arbirary, may be anywhere on disk or external storage.
                /// Such images are managed by the user, not the app, and thus are not cloned when saving state.
                outputDevices.append(device)
                continue
            }

            let inputURL: URL = model.diskImageURL(for: device)
            let cloneURL: URL = packageURL.appending(path: inputURL.lastPathComponent)

            try FileManager.default.copyItem(at: inputURL, to: cloneURL)

            device.isSavedStateClone = true

            outputDevices.append(device)
        }

        return outputDevices
    }

    mutating func createStorageDeviceClones(packageURL: URL, model: VBVirtualMachine) async throws {
        storageDevices = try await Self.createStorageDeviceClones(packageURL: packageURL, model: model)
    }
}
