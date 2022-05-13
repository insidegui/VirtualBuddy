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

        var virtualCPUCount = totalAvailableCPUs <= 1 ? 1 : totalAvailableCPUs - 1
        virtualCPUCount = max(virtualCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        virtualCPUCount = min(virtualCPUCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)

        return virtualCPUCount
    }

    func computeMemorySize() -> UInt64 {
        // We arbitrarily choose 4GB.
        var memorySize = (16 * 1024 * 1024 * 1024) as UInt64
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

    func createBlockDeviceConfiguration() -> VZVirtioBlockDeviceConfiguration {
        guard let diskImageAttachment = try? VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: vm.diskImagePath), readOnly: false) else {
            fatalError("Failed to create Disk image.")
        }
        let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)
        return disk
    }
    
    func createAdditionalBlockDevice() -> VZVirtioBlockDeviceConfiguration? {
        let url = URL(fileURLWithPath: vm.extraDiskImagePath)
        
        if !FileManager.default.fileExists(atPath: vm.extraDiskImagePath) {
            return nil
        }
        
        do {
            let diskImageAttachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
            
            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)
            
            return disk
        } catch {
            fatalError("Failed to create Disk image: \(error)")
        }
    }
    
    private func createDiskImage(at url: URL) {
        let diskFd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if diskFd == -1 {
            fatalError("Cannot create disk image.")
        }

        // 64GB disk space.
        var result = ftruncate(diskFd, 64 * 1024 * 1024 * 1024)
        if result != 0 {
            fatalError("ftruncate() failed.")
        }

        result = close(diskFd)
        if result != 0 {
            fatalError("Failed to close the disk image.")
        }
    }

    func createNetworkDeviceConfiguration() -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()

        let networkAttachment = VZNATNetworkDeviceAttachment()
        networkDevice.attachment = networkAttachment
        return networkDevice
    }
    
    func createPointingDeviceConfiguration() -> VZPointingDeviceConfiguration {
        return _VZMacTrackpadConfiguration()
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
        guard let screen = NSScreen.main else { return .fallback }

        guard let resolution = screen.deviceDescription[.resolution] as? NSSize else { return .fallback }
        guard let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }
        
        let pointHeight = size.height - screen.safeAreaInsets.top

        return VZMacGraphicsDisplayConfiguration(
            widthInPixels: Int(size.width * screen.backingScaleFactor),
            heightInPixels: Int(pointHeight * screen.backingScaleFactor),
            pixelsPerInch: Int(resolution.width)
        )
    }
    
}
