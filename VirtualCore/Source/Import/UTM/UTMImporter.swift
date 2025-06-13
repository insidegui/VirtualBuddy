import Foundation
import BuddyFoundation
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: "UTMImporter")

extension UTType {
    static let utmBundle = UTType(importedAs: "com.utmapp.utm")
}

struct UTMImporter: VMImporter {
    let appName = "UTM"
    let fileType = UTType.utmBundle

    @discardableResult
    func importVirtualMachine(from path: FilePath, into library: VMLibraryController) async throws -> VBVirtualMachine {
        let errorPrefix = "This \(appName) virtual machine has a configuration that’s not supported by VirtualBuddy."

        let configPath = path + "config.plist"
        try configPath.isFile.require("\(errorPrefix) Missing a config.plist file.")

        logger.debug("Config file path is \(configPath.string.quoted)")

        let dataPath = path + "Data"
        try dataPath.isDirectory.require("\(errorPrefix) Missing a \"Data\" directory.")

        logger.debug("Data path is \(dataPath.string.quoted)")

        let config = try UTMAppleConfiguration(path: configPath)

        logger.debug("Loaded UTM configuration with backend \(String(optional: config.backend?.quoted), privacy: .public), version \(String(optional: config.configurationVersion), privacy: .public)")

        let isMac = config.system.boot.operatingSystem != .linux

        try isMac.require("VirtualBuddy can only import Mac virtual machines from \(appName).")

        let drives = config.drives
        try (!drives.isEmpty).require("\(errorPrefix) No storage devices available. Needs at least a boot drive.")

        var model = try createBundle(forImportedVMPath: path, library: library)

        func createStorageDevice(for drive: UTMAppleConfigurationDrive, isBootDrive: Bool) throws -> VBStorageDevice {
            let imageName = try drive.imageName.require("\(errorPrefix) Boot drive is missing an image name.")

            let imageSource = dataPath + imageName

            logger.debug("Image source is \(imageSource)")

            try imageSource.isFile.require("\(errorPrefix) Storage device image not found at \(imageSource.string.quoted).")

            var image = if isBootDrive {
                VBManagedDiskImage.managedBootImage
            } else {
                VBManagedDiskImage(filename: imageSource.lastComponentWithoutExtension, size: 0)
            }

            image.size = UInt64(imageSource.fileSize ?? 0)

            /// ``VBManagedDiskImage/filename`` is the name without a file extension, which is respected by ``VBManagedDiskImage/managedBootImage``, but in UTM configs the image name includes the file extension.
            /// When importing from UTM, the file extension is removed from the image name and re-added here.
            let libraryImagePath = (FilePath(model.bundleURL) + image.filename).appendingExtension(image.format.fileExtension)

            logger.debug("Copying disk to VirtualBuddy bundle disk path \(libraryImagePath)")

            try imageSource.copy(libraryImagePath)

            return VBStorageDevice(utmDrive: drive, image: image, isBootDrive: isBootDrive)
        }

        if isMac {
            logger.debug("Detected Mac platform, gathering platform data files")

            let platform = try config.system.macPlatform.require("\(errorPrefix) Mac virtual machine is missing a Mac platform configuration.")

            let auxStorageName = platform.auxiliaryStoragePath ?? "AuxiliaryStorage"
            let auxStorageSource = dataPath + FilePath(auxStorageName)

            try auxStorageSource.isFile.require("\(errorPrefix) Mac platform file \(auxStorageName.quoted) was not found in \(dataPath.lastComponent.quoted) directory.")

            try auxStorageSource.copy(FilePath(model.auxiliaryStorageURL))

            try platform.hardwareModel.write(to: model.hardwareModelURL)
            logger.debug("Wrote hardware model to \(model.hardwareModelURL.path)")

            try platform.machineIdentifier.write(to: model.machineIdentifierURL)
            logger.debug("Wrote machine identifier to \(model.machineIdentifierURL.path)")
        }

        model.metadata = VBVirtualMachine.Metadata(utm: config)
        model.configuration = VBMacConfiguration(utm: config)

        for (index, drive) in drives.enumerated() {
            logger.debug("Processing drive #\(index)")

            let device = try createStorageDevice(for: drive, isBootDrive: index == 0)

            model.configuration.hardware.storageDevices.append(device)
        }

        return model
    }
}

private extension VBVirtualMachine.Metadata {
    init(utm: UTMAppleConfiguration) {
        self.init(
            uuid: UUID(uuidString: utm.information.uuid) ?? UUID(),
            version: VBVirtualMachine.Metadata.currentVersion,
            installFinished: true,
            firstBootDate: nil,
            lastBootDate: nil,
            backgroundHash: .virtualBuddyBackground,
            remoteInstallImageURL: nil,
            installImageURL: nil
        )
    }
}

private extension VBMacConfiguration {
    init(utm: UTMAppleConfiguration) {
        self.init(
            systemType: utm.system.boot.operatingSystem == .linux ? .linux : .mac,
            hardware: VBMacDevice(utm: utm),
            sharedFolders: [],
            guestAdditionsEnabled: true,
            rosettaSharingEnabled: utm.virtualization.hasRosetta == true,
            captureSystemKeys: true
        )
    }
}

private extension VBMacDevice {
    private static let utmBytesInMib = UInt64(1048576)

    init(utm: UTMAppleConfiguration) {
        self.init(
            cpuCount: utm.system.cpuCount,
            memorySize: UInt64(utm.system.memorySize) * Self.utmBytesInMib,
            pointingDevice: utm.virtualization.pointer == .trackpad ? .trackpad : .mouse,
            keyboardDevice: utm.virtualization.keyboard == .mac ? .mac : .generic,
            displayDevices: utm.displays.map(VBDisplayDevice.init(utm:)),
            networkDevices: utm.networks.map(VBNetworkDevice.init(utm:)),
            soundDevices: [VBSoundDevice(utm: utm.virtualization)].compactMap { $0 },
            storageDevices: []
        )
    }
}

private extension VBDisplayDevice {
    init(utm: UTMAppleConfigurationDisplay) {
        self.init(
            id: UUID(),
            name: "Default",
            width: utm.widthInPixels,
            height: utm.heightInPixels,
            pixelsPerInch: utm.pixelsPerInch,
            automaticallyReconfiguresDisplay: utm.isDynamicResolution
        )
    }
}

private extension VBNetworkDevice {
    init(utm: UTMAppleConfigurationNetwork) {
        let kind: Kind = utm.mode == .bridged ? .bridge : .NAT

        let id: String = if kind == .bridge {
            if let interface = utm.bridgeInterface {
                interface
            } else {
                Self.automaticBridgeID
            }
        } else {
            Self.defaultID
        }

        self.init(
            id: id,
            name: "Default",
            kind: kind,
            macAddress: utm.macAddress
        )
    }
}

private extension VBSoundDevice {
    init?(utm: UTMAppleConfigurationVirtualization) {
        guard utm.hasAudio else { return nil }

        self.init(enableOutput: utm.hasAudio, enableInput: utm.hasAudio)
    }
}

private extension VBStorageDevice {
    init(utmDrive: UTMAppleConfigurationDrive, image: VBManagedDiskImage, isBootDrive: Bool) {
        self.init(
            id: utmDrive.identifier,
            isBootVolume: isBootDrive,
            isEnabled: true,
            isReadOnly: utmDrive.isReadOnly,
            isUSBMassStorageDevice: false,
            backing: .managedImage(image)
        )
    }
}
