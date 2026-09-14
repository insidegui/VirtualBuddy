/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization
import BuddyFoundation
import ManagedPreferencesKit

protocol VirtualMachineConfigurationHelper {
    var vm: VBVirtualMachine { get }
    var savedState: VBSavedStatePackage? { get }
    func createInstallDevice(installImageURL: URL) throws -> VZStorageDeviceConfiguration
    func createBootLoader() throws -> VZBootLoader
    func createBootBlockDevice() async throws -> VZVirtioBlockDeviceConfiguration
    func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration]
    func createKeyboardConfiguration() -> VZKeyboardConfiguration
    func createGraphicsDevices() -> [VZGraphicsDeviceConfiguration]
    func createEntropyDevices() -> [VZVirtioEntropyDeviceConfiguration]
    @available(macOS 13.0, *)
    func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration?
    @available(macOS 15.0, *)
    func createUSBControllers() -> [VZUSBControllerConfiguration]
}

func createVZDiskImageStorageDeviceAttachment(url: URL, readOnly: Bool, guestType: VBGuestType) throws -> VZDiskImageStorageDeviceAttachment {
    if guestType == .linux {
        // Linux guest is bound to cause IO errors.
        // Referring to https://github.com/utmapp/UTM/issues/4840, seems like setting the cachingMode to cached
        // fixes this IO errors and disk corruption issues for Linux guest.
        return try VZDiskImageStorageDeviceAttachment(url: url, readOnly: readOnly, cachingMode: .cached, synchronizationMode: .fsync)
    } else {
        // macOS guests also need cached mode to prevent APFS corruption under heavy I/O.
        // See: UTM #4840, Lima VM #1957
        return try VZDiskImageStorageDeviceAttachment(url: url, readOnly: readOnly, cachingMode: .cached, synchronizationMode: .fsync)
    }
}

extension VirtualMachineConfigurationHelper {

    var storageDeviceContainer: VBStorageDeviceContainer { savedState ?? vm }

    func createBootBlockDevice() async throws -> VZVirtioBlockDeviceConfiguration {
        do {
            let bootDevice = try storageDeviceContainer.bootDevice
            let bootDiskImage = try storageDeviceContainer.bootDiskImage
            
            if !bootDevice.diskImageExists(for: storageDeviceContainer) {
                guard storageDeviceContainer.allowDiskImageCreation else {
                    throw Failure("Boot disk image does not exist.")
                }

                let settings = DiskImageGenerator.ImageSettings(for: bootDiskImage, in: vm)
                try await DiskImageGenerator.generateImage(with: settings)
            }

            let bootURL = storageDeviceContainer.diskImageURL(for: bootDiskImage)
            let diskImageAttachment = try createVZDiskImageStorageDeviceAttachment(url: bootURL, readOnly: false, guestType: vm.configuration.systemType)

            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)

            return disk
        } catch {
            throw Failure("Failed to instantiate a disk image for the VM: \(error.localizedDescription).")
        }
    }
    
    func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration] {
        try storageDeviceContainer.additionalBlockDevices(guestType: vm.configuration.systemType)
    }

    func createKeyboardConfiguration() -> VZKeyboardConfiguration {
        VZUSBKeyboardConfiguration()
    }

    func createEntropyDevices() -> [VZVirtioEntropyDeviceConfiguration] { [] }

    @available(macOS 13.0, *)
    func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration? { nil }

    @available(macOS 15.0, *)
    func createUSBControllers() -> [VZUSBControllerConfiguration] { [] }

}

extension VBStorageDeviceContainer {
    func additionalBlockDevices(guestType: VBGuestType) throws -> [VZVirtioBlockDeviceConfiguration] {
        var output = [VZVirtioBlockDeviceConfiguration]()

        for device in storageDevices {
            guard device.isEnabled, !device.isBootVolume else { continue }

            let url = diskImageURL(for: device)
            let attachment = try createVZDiskImageStorageDeviceAttachment(url: url, readOnly: device.isReadOnly, guestType: guestType)

            output.append(VZVirtioBlockDeviceConfiguration(attachment: attachment))
        }

        return output
    }
}

extension VBMacConfiguration {

    var vzNetworkDevices: [VZNetworkDeviceConfiguration] {
        get throws {
            try hardware.networkDevices.map { try $0.vzConfiguration }
        }
    }

    var vzAudioDevices: [VZAudioDeviceConfiguration] {
        hardware.soundDevices.map(\.vzConfiguration)
    }

    var vzPointingDevices: [VZPointingDeviceConfiguration] {
        get throws { try hardware.pointingDevice.vzConfigurations }
    }

}

extension VBNetworkDevice {

    var vzConfiguration: VZNetworkDeviceConfiguration {
        get throws {
            let config = VZVirtioNetworkDeviceConfiguration()

            guard let addr = VZMACAddress(string: macAddress) else {
                throw Failure("Invalid MAC address")
            }

            config.macAddress = addr
            config.attachment = try vzAttachment

            return config
        }
    }

    private var vzAttachment: VZNetworkDeviceAttachment? {
        get throws {
            try makeAttachment(preferences: VirtualBuddyManagedPreferences.schema.reader())
        }
    }

    func makeAttachment(preferences: ManagedPreferenceReader<VirtualBuddyManagedPreferences>) throws -> VZNetworkDeviceAttachment? {
        switch kind {
        case .NAT:
            return VZNATNetworkDeviceAttachment()
        case .bridge:
            guard !preferences.value(for: .disableBridgedNetworking, default: false) else {
                VirtualBuddyManagedPreferences.logger.notice("Bridged network adapter disconnected by DisableBridgedNetworking")
                return nil
            }
            let interface = try resolveBridge(with: id)
            return VZBridgedNetworkDeviceAttachment(interface: interface)
        }
    }

    private func resolveBridge(with identifier: String) throws -> VZBridgedNetworkInterface {
        guard identifier != VBNetworkDeviceInterface.automatic.id else {
            return try VZBridgedNetworkInterface.networkInterfaces.first.require("There are no network interfaces available on the host for bridging.")
        }

        return try VZBridgedNetworkInterface.networkInterfaces.first(where: { $0.identifier == identifier })
            .require("The bridged network interface \(identifier.quoted) is not available.")
    }
}

extension VBPointingDevice {

    var vzConfigurations: [VZPointingDeviceConfiguration] {
        get throws {
            switch kind {
            case .mouse:
                return [VZUSBScreenCoordinatePointingDeviceConfiguration()]
            case .trackpad:
                return [
                    VZMacTrackpadConfiguration(),
                    VZUSBScreenCoordinatePointingDeviceConfiguration()
                ]
            }
        }
    }

}

extension VBSoundDevice {

    var vzConfiguration: VZAudioDeviceConfiguration {
        makeConfiguration(preferences: VirtualBuddyManagedPreferences.schema.reader())
    }

    func makeConfiguration(preferences: ManagedPreferenceReader<VirtualBuddyManagedPreferences>) -> VZAudioDeviceConfiguration {
        let audioConfiguration = VZVirtioSoundDeviceConfiguration()

        if enableInput {
            let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
            if preferences.value(for: .disableMicrophoneInput, default: false) {
                // A nil source produces silence, preserving the device topology for snapshots.
                VirtualBuddyManagedPreferences.logger.notice("Host microphone source omitted by DisableMicrophoneInput")
            } else {
                inputStream.source = VZHostAudioInputStreamSource()
            }
            audioConfiguration.streams.append(inputStream)
        }

        if enableOutput {
            let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
            outputStream.sink = VZHostAudioOutputStreamSink()
            audioConfiguration.streams.append(outputStream)
        }

        return audioConfiguration
    }

}

extension VBMacConfiguration {
    
    var vzSharedFoldersFileSystemDevices: [VZDirectorySharingDeviceConfiguration] {
        get throws {
            try makeSharedFoldersFileSystemDevices(preferences: VirtualBuddyManagedPreferences.schema.reader())
        }
    }

    func makeSharedFoldersFileSystemDevices(preferences: ManagedPreferenceReader<VirtualBuddyManagedPreferences>) throws -> [VZDirectorySharingDeviceConfiguration] {
        var directories: [String: VZSharedDirectory] = [:]

        if preferences.value(for: .disableSharedFolders, default: false) {
            VirtualBuddyManagedPreferences.logger.notice("Host folder mappings ignored by DisableSharedFolders")
        } else {
            for folder in sharedFolders {
                guard let dir = folder.vzSharedFolder else { continue }

                directories[folder.effectiveMountPointName] = dir
            }
        }

        var devices: [VZDirectorySharingDeviceConfiguration] = []

        // Keep the device topology stable for snapshots, even when policy leaves the share empty.
        try VZVirtioFileSystemDeviceConfiguration.validateTag(VBSharedFolder.virtualBuddyShareName)
        do {
            let share = VZMultipleDirectoryShare(directories: directories)
            let device = VZVirtioFileSystemDeviceConfiguration(tag: VBSharedFolder.virtualBuddyShareName)
            device.share = share
            devices.append(device)
        }

        if self.systemType == .linux && self.rosettaSharingEnabled {
            // Rosetta directory share for Linux VMs
            try VZVirtioFileSystemDeviceConfiguration.validateTag(VBSharedFolder.rosettaShareName)
            let share = try VZLinuxRosettaDirectoryShare()
            let device = VZVirtioFileSystemDeviceConfiguration(tag: VBSharedFolder.rosettaShareName)
            device.share = share
            devices.append(device)
        }

        return devices
    }
}

extension VBSharedFolder {
    
    var vzSharedFolder: VZSharedDirectory? {
        guard isAvailable, isEnabled else { return nil }
        return VZSharedDirectory(url: url, readOnly: isReadOnly)
    }
    
}

extension VZVirtualMachineConfiguration {
    func validateMicrophonePolicy(preferences: ManagedPreferenceReader<VirtualBuddyManagedPreferences>) throws {
        guard preferences.value(for: .disableMicrophoneInput, default: false) else { return }
        let inputs = audioDevices.compactMap { $0 as? VZVirtioSoundDeviceConfiguration }
            .flatMap(\.streams).compactMap { $0 as? VZVirtioSoundDeviceInputStreamConfiguration }
        guard !inputs.contains(where: { $0.source != nil }) else {
            VirtualBuddyManagedPreferences.logger.notice("VM start or resume denied by DisableMicrophoneInput; a cold start is required")
            throw Failure("Microphone input is disabled by your organization. Shut down and start this virtual machine to apply the restriction.")
        }
    }
}
