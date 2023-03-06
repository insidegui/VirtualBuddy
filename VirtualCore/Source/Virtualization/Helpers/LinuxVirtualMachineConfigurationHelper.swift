/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

@available(macOS 13.0, *)
struct LinuxVirtualMachineConfigurationHelper: VirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    
    func createInstallDevice(installImageURL: URL) throws -> VZStorageDeviceConfiguration {
        let attachment = try VZDiskImageStorageDeviceAttachment(url: installImageURL, readOnly: true)
        let usbDeviceConfiguration = VZUSBMassStorageDeviceConfiguration(attachment: attachment)
        return usbDeviceConfiguration
    }

    func createBootLoader() throws -> VZBootLoader {
        let efi = VZEFIBootLoader()
        let storeURL = vm.metadataDirectoryURL.appendingPathComponent("nvram")
        if FileManager.default.fileExists(atPath: storeURL.path) {
            efi.variableStore = VZEFIVariableStore(url: storeURL)
        } else {
            efi.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: storeURL, options: [])
        }
        return efi
    }

    func createGraphicsDevices() -> [VZGraphicsDeviceConfiguration] {
        let graphicsConfiguration = VZVirtioGraphicsDeviceConfiguration()

        graphicsConfiguration.scanouts = vm.configuration.hardware.displayDevices.map(\.vzScanout)

        return [graphicsConfiguration]
    }
}

// MARK: - Configuration Models -> Virtualization

@available(macOS 13.0, *)
extension VBDisplayDevice {

    var vzScanout: VZVirtioGraphicsScanoutConfiguration {
        VZVirtioGraphicsScanoutConfiguration(widthInPixels: width, heightInPixels: height)
    }

}
