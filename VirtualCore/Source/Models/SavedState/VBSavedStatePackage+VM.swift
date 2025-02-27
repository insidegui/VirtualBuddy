import Foundation

extension VBSavedStatePackage: VBStorageDeviceContainer {
    public var bundleURL: URL { url }
    public var storageDevices: [VBStorageDevice] { metadata.storageDevices }
}
