/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

protocol VirtualMachineConfigurationHelper {
    var vm: VBVirtualMachine { get }
    func createInstallDevice(installImageURL: URL) throws -> VZStorageDeviceConfiguration
    func createBootLoader() throws -> VZBootLoader
    func createBootBlockDevice() async throws -> VZVirtioBlockDeviceConfiguration
    func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration]
    func createKeyboardConfiguration() -> VZKeyboardConfiguration
    func createGraphicsDevices() -> [VZGraphicsDeviceConfiguration]
    func createEntropyDevices() -> [VZVirtioEntropyDeviceConfiguration]
    @available(macOS 13.0, *)
    func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration?
}

extension VirtualMachineConfigurationHelper {

    func createBootBlockDevice() async throws -> VZVirtioBlockDeviceConfiguration {
        do {
            let bootDevice = try vm.bootDevice
            let bootDiskImage = try vm.bootDiskImage
            
            if !bootDevice.diskImageExists(for: vm) {
                let settings = DiskImageGenerator.ImageSettings(for: bootDiskImage, in: vm)
                try await DiskImageGenerator.generateImage(with: settings)
            }

            let bootURL = vm.diskImageURL(for: bootDiskImage)
            let diskImageAttachment = try VZDiskImageStorageDeviceAttachment(url: bootURL, readOnly: false)

            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)

            return disk
        } catch {
            throw Failure("Failed to instantiate a disk image for the VM: \(error.localizedDescription).")
        }
    }
    
    func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration] {
        try vm.additionalBlockDevices
    }

    func createKeyboardConfiguration() -> VZKeyboardConfiguration {
        VZUSBKeyboardConfiguration()
    }

    func createEntropyDevices() -> [VZVirtioEntropyDeviceConfiguration] { [] }

    @available(macOS 13.0, *)
    func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration? { nil }

}

extension VBVirtualMachine {
    var additionalBlockDevices: [VZVirtioBlockDeviceConfiguration] {
        get throws {
            var output = [VZVirtioBlockDeviceConfiguration]()

            for device in configuration.hardware.storageDevices {
                guard device.isEnabled, !device.isBootVolume else { continue }

                let url = diskImageURL(for: device)
                let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: device.isReadOnly)

                output.append(VZVirtioBlockDeviceConfiguration(attachment: attachment))
            }

            return output
        }
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

    private var vzAttachment: VZNetworkDeviceAttachment {
        get throws {
            switch kind {
            case .NAT:
                return VZNATNetworkDeviceAttachment()
            case .bridge:
                let interface = try resolveBridge(with: id)
                return VZBridgedNetworkDeviceAttachment(interface: interface)
            }
        }
    }

    private func resolveBridge(with identifier: String) throws -> VZBridgedNetworkInterface {
        guard let iface = VZBridgedNetworkInterface.networkInterfaces.first(where: { $0.identifier == identifier }) else {
            throw Failure("Couldn't find the specified network interface for bridging")
        }
        return iface
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
        let audioConfiguration = VZVirtioSoundDeviceConfiguration()

        if enableInput {
            let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
            inputStream.source = VZHostAudioInputStreamSource()
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
            var directories: [String: VZSharedDirectory] = [:]
            
            for folder in sharedFolders {
                guard let dir = folder.vzSharedFolder else { continue }
                
                directories[folder.effectiveMountPointName] = dir
            }

            var devices: [VZDirectorySharingDeviceConfiguration] = []

            // standard directory share
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
}

extension VBSharedFolder {
    
    var vzSharedFolder: VZSharedDirectory? {
        guard isAvailable, isEnabled else { return nil }
        return VZSharedDirectory(url: url, readOnly: isReadOnly)
    }
    
}
