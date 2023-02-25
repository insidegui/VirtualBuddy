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
}

// MARK: - Configuration Models -> Virtualization

extension VBDisplayDevice {

    var vzDisplay: VZMacGraphicsDisplayConfiguration {
        VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: pixelsPerInch)
    }

}
