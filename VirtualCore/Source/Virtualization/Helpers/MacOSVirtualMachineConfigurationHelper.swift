/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

struct MacOSVirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    
    func computeCPUCount() -> Int {
        let totalAvailableCPUs = ProcessInfo.processInfo.processorCount

        var virtualCPUCount = totalAvailableCPUs <= 1 ? 1 : totalAvailableCPUs / 2
        virtualCPUCount = max(virtualCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        virtualCPUCount = min(virtualCPUCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)

        return virtualCPUCount
    }

    func computeMemorySize() -> UInt64 {
        let hostMemory = ProcessInfo.processInfo.physicalMemory
        var memorySize = hostMemory / 2
        memorySize = max(memorySize, VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        memorySize = min(memorySize, VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        return memorySize
    }

    func createBootLoader() -> VZMacOSBootLoader {
        return VZMacOSBootLoader()
    }

    func createGraphicsDeviceConfiguration() -> VZMacGraphicsDeviceConfiguration {
        let graphicsConfiguration = VZMacGraphicsDeviceConfiguration()
        graphicsConfiguration.displays = [
            VZMacGraphicsDisplayConfiguration.mainScreen
        ]

        return graphicsConfiguration
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
    
    func createAdditionalBlockDevice() throws -> VZVirtioBlockDeviceConfiguration? {
        let url = URL(fileURLWithPath: vm.extraDiskImagePath)
        
        if !FileManager.default.fileExists(atPath: vm.extraDiskImagePath) {
            return nil
        }
        
        do {
            let diskImageAttachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
            
            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)
            
            return disk
        } catch {
            throw Failure("Failed to create Disk image: \(error)")
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

    func createNetworkDeviceConfiguration() -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()

        let networkAttachment = VZNATNetworkDeviceAttachment()
        networkDevice.attachment = networkAttachment
        return networkDevice
    }

    func createPointingDeviceConfiguration2() -> VZPointingDeviceConfiguration {
        return VZUSBScreenCoordinatePointingDeviceConfiguration()
    }
    
    func createMultiTouchDeviceConfiguration() -> _VZMultiTouchDeviceConfiguration {
        return _VZAppleTouchScreenConfiguration()
    }

    func createKeyboardConfiguration() -> VZUSBKeyboardConfiguration {
        return VZUSBKeyboardConfiguration()
    }

    func createAudioDeviceConfiguration() -> VZVirtioSoundDeviceConfiguration {
        let audioConfiguration = VZVirtioSoundDeviceConfiguration()

        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()

        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()

        audioConfiguration.streams = [inputStream, outputStream]
        return audioConfiguration
    }
    
}

extension VZMacGraphicsDisplayConfiguration {
    
    static let fallback = VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1080, pixelsPerInch: 144)
    
    /// A configuration matching the host's main screen.
    static var mainScreen: VZMacGraphicsDisplayConfiguration {
        guard let screen = NSScreen.main,
              let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }

        return VZMacGraphicsDisplayConfiguration(for: screen, sizeInPoints: size)
    }
    
}

public extension Int {
    static let defaultDiskImageSize = 64 * 1_000_000_000
    static let minimumDiskImageSize = 64 * 1_000_000_000
    static let maximumDiskImageSize = 512 * 1_000_000_000
}
