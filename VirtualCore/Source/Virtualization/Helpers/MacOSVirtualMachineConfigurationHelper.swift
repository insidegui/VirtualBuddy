/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

struct MacOSVirtualMachineConfigurationHelper: VirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    let savedState: VBSavedStatePackage?

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
        var devices = try storageDeviceContainer.additionalBlockDevices(guestType: vm.configuration.systemType)

        if vm.configuration.guestAdditionsEnabled,
           vm.configuration.systemType.supportsGuestApp,
           let disk = try? VZVirtioBlockDeviceConfiguration.guestAdditionsDisk {
            devices.append(disk)
        }

        return devices
    }

    func createKeyboardConfiguration() -> VZKeyboardConfiguration {
        if #available(macOS 14.0, *) {
            switch vm.configuration.hardware.keyboardDevice.kind {
            case .generic:
                return VZUSBKeyboardConfiguration()
            case .mac:
                return VZMacKeyboardConfiguration()
            }
        } else {
            return VZUSBKeyboardConfiguration()
        }
    }

    func createEntropyDevices() -> [VZEntropyDeviceConfiguration] {
        [VZVirtioEntropyDeviceConfiguration()]
    }

    @available(macOS 15.0, *)
    func createUSBControllers() -> [VZUSBControllerConfiguration] {
        let xhci = VZXHCIControllerConfiguration()
        return [xhci]
    }
}

// MARK: - Configuration Models -> Virtualization

extension VBDisplayDevice {

    var vzDisplay: VZMacGraphicsDisplayConfiguration {
        VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: pixelsPerInch)
    }

}
