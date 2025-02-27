import Foundation

/// Adopted by ``VMVirtualMachine`` and ``VBSavedStatePackage``
/// in order to help resolve storage devices when bootstrapping a VM.
public protocol VBStorageDeviceContainer {
    var bundleURL: URL { get }
    var storageDevices: [VBStorageDevice] { get }
    var bootDevice: VBStorageDevice { get throws }
    var bootDiskImage: VBManagedDiskImage { get throws }
    var allowDiskImageCreation: Bool { get }
    func diskImageURL(for image: VBManagedDiskImage) -> URL
    func diskImageURL(for device: VBStorageDevice) -> URL
}

// MARK: - Default Implementations

/// These default implementations take care of resolving disk images for both ``VBVirtualMachine`` and ``VBSavedStatePackage``.
/// Which one is used will be determine in `VirtualMachineConfigurationHelper` when bootstrapping the VM.
public extension VBStorageDeviceContainer {
    var allowDiskImageCreation: Bool { false }

    var bootDevice: VBStorageDevice {
        get throws {
            guard let device = storageDevices.first(where: { $0.isBootVolume }) else {
                throw Failure("The virtual machine lacks a bootable storage device.")
            }

            return device
        }
    }

    var bootDiskImage: VBManagedDiskImage {
        get throws {
            let device = try bootDevice

            guard case .managedImage(let image) = device.backing else {
                throw Failure("The boot device must use a disk image managed by VirtualBuddy")
            }

            return image
        }
    }

    func diskImageURL(for image: VBManagedDiskImage) -> URL {
        bundleURL
            .appendingPathComponent(image.filename)
            .appendingPathExtension(image.format.fileExtension)
    }

    func diskImageURL(for device: VBStorageDevice) -> URL {
        switch device.backing {
        case .managedImage(let image):
            return diskImageURL(for: image)
        case .customImage(let customURL):
            return customURL
        }
    }
}
