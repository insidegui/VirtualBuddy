/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

struct MacOSVirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    
    func createBootLoader() -> VZMacOSBootLoader {
        return VZMacOSBootLoader()
    }

    func createBlockDeviceConfiguration() throws -> VZVirtioBlockDeviceConfiguration {
        do {
            let diskURL = URL(fileURLWithPath: vm.diskImagePath)

            if !FileManager.default.fileExists(atPath: diskURL.path) {
                let size = vm.installOptions?.diskImageSize ?? .defaultDiskImageSize
                try createDiskImage(ofSize: size, at: diskURL)
            }

            let diskImageAttachment = try VZDiskImageStorageDeviceAttachment(url: diskURL, readOnly: false)

            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)

            return disk
        } catch {
            throw Failure("Failed to instantiate a disk image for the VM: \(error.localizedDescription).")
        }
    }

    private func createDiskImage(ofSize size: Int, at url: URL) throws {
        let diskFd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if diskFd == -1 {
            throw Failure("Cannot create disk image.")
        }

        var result = ftruncate(diskFd, off_t(size))
        if result != 0 {
            throw Failure("ftruncate() failed.")
        }

        result = close(diskFd)
        if result != 0 {
            throw Failure("Failed to close the disk image.")
        }
    }

    func createKeyboardConfiguration() -> VZUSBKeyboardConfiguration {
        return VZUSBKeyboardConfiguration()
    }

}

public extension Int {
    static let defaultDiskImageSize = 64 * 1_000_000_000
    static let minimumDiskImageSize = 64 * 1_000_000_000
    static let maximumDiskImageSize = 512 * 1_000_000_000
}

// MARK: - Configuration Models -> Virtualization

extension VBMacConfiguration {

    var vzDisplays: [VZMacGraphicsDisplayConfiguration] {
        hardware.displayDevices.map(\.vzDisplay)
    }

    var vzNetworkDevices: [VZNetworkDeviceConfiguration] {
        get throws {
            try hardware.networkDevices.map { try $0.vzConfiguration }
        }
    }

    var vzAudioDevices: [VZAudioDeviceConfiguration] {
        hardware.soundDevices.map(\.vzConfiguration)
    }

    var vzPointingDevices: [VZPointingDeviceConfiguration] {
        get throws { [try hardware.pointingDevice.vzConfiguration] }
    }

    var vzGraphicsDevices: [VZGraphicsDeviceConfiguration] {
        let graphicsConfiguration = VZMacGraphicsDeviceConfiguration()

        graphicsConfiguration.displays = vzDisplays

        return [graphicsConfiguration]
    }

}

extension VBDisplayDevice {

    var vzDisplay: VZMacGraphicsDisplayConfiguration {
        VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: pixelsPerInch)
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

    var vzConfiguration: VZPointingDeviceConfiguration {
        get throws {
            switch kind {
            case .mouse:
                return VZUSBScreenCoordinatePointingDeviceConfiguration()
            case .trackpad:
                guard #available(macOS 13.0, *) else {
                    throw Failure("The trackpad pointing device is only available on macOS 13 and later")
                }
                return VZMacTrackpadConfiguration()
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
    
    @available(macOS 13.0, *)
    var vzClipboardSyncDevice: VZVirtioConsoleDeviceConfiguration? {
        #if ENABLE_SPICE_CLIPBOARD_SYNC
        let device = VZVirtioConsoleDeviceConfiguration()
        
        let port = VZVirtioConsolePortConfiguration()
        port.name = VZSpiceAgentPortAttachment.spiceAgentPortName
        let attachment = VZSpiceAgentPortAttachment()
        attachment.sharesClipboard = sharedClipboardEnabled
        port.attachment = attachment
        device.ports[0] = port
        
        print("attachment.sharesClipboard = \(attachment.sharesClipboard)")
        
        return device
        #else
        return nil
        #endif
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
            
            try VZVirtioFileSystemDeviceConfiguration.validateTag(VBSharedFolder.virtualBuddyShareName)
            
            let share = VZMultipleDirectoryShare(directories: directories)
            let device = VZVirtioFileSystemDeviceConfiguration(tag: VBSharedFolder.virtualBuddyShareName)
            device.share = share
            return [device]
        }
    }
    
}

extension VBSharedFolder {
    
    var vzSharedFolder: VZSharedDirectory? {
        guard isAvailable, isEnabled else { return nil }
        return VZSharedDirectory(url: url, readOnly: isReadOnly)
    }
    
}
