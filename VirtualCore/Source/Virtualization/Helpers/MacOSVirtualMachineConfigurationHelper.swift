/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

struct MacOSVirtualMachineConfigurationHelper: VirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    
    func createInstallDevice(installImageURL: URL) throws -> VZStorageDeviceConfiguration {
        fatalError()
    }

    func createBootLoader() -> VZBootLoader {
        return VZMacOSBootLoader()
    }

    func createGraphicsDevices() -> [VZGraphicsDeviceConfiguration] {
        let graphicsConfiguration = VZMacGraphicsDeviceConfiguration()
        
        graphicsConfiguration.displays = vm.configuration.hardware.displayDevices.map(\.vzDisplay)
        
        return [graphicsConfiguration]
    }

    func createAdditionalBlockDevices() async throws -> [VZVirtioBlockDeviceConfiguration] {
        var devices = try vm.additionalBlockDevices

        if vm.configuration.guestAdditionsEnabled {
            let guestDisk = try VZVirtioBlockDeviceConfiguration.guestAdditionsDisk
            devices.append(guestDisk)
        }

        return devices
    }

    func createKeyboardConfiguration() -> VZKeyboardConfiguration {
        if #available(macOS 14.0, *) {
            return VZMacKeyboardConfiguration()
        } else {
            return VZUSBKeyboardConfiguration()
        }
    }

    func createEntropyDevices() -> [VZEntropyDeviceConfiguration] {
        [VZVirtioEntropyDeviceConfiguration()]
    }
}

// MARK: - Configuration Models -> Virtualization

extension VBDisplayDevice {

    var vzDisplay: VZMacGraphicsDisplayConfiguration {
        VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: pixelsPerInch)
    }

}
