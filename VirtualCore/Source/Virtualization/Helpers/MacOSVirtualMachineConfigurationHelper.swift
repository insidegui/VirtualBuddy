/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Helper that creates various configuration objects exposed in the `VZVirtualMachineConfiguration`.
*/

import Foundation
import Virtualization

struct MacOSVirtualMachineConfigurationHelper: VirtualMachineConfigurationHelper {
    let vm: VBVirtualMachine
    let restoration: SavedSessionRestoration?

    init(vm: VBVirtualMachine, restoration: SavedSessionRestoration? = nil) {
        self.vm = vm
        self.restoration = restoration
    }

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

        if let mediaURL = await guestAdditionsMediaURL() {
            do {
                devices.append(try VZVirtioBlockDeviceConfiguration.guestAdditionsDisk(imageURL: mediaURL))
            } catch {
                assertionFailure("VZVirtioBlockDeviceConfiguration initialization failed for guest additions disk: \(error)")
            }
        }

        return devices
    }

    func guestAdditionsMediaURL() async -> URL? {
        guard vm.configuration.guestAdditionsEnabled, await vm.guestAppSupport != .unsupported else { return nil }

        /// A restored session keeps the exact image that was attached when it was saved.
        if let restoration { return restoration.guestAdditionsMediaURL }

        return VZVirtioBlockDeviceConfiguration.guestAdditionsImageURL(for: vm.configuration)
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

    @available(macOS 27.0, *)
    static func createProvisioningOptions(for vm: VBVirtualMachine) -> VZMacGuestProvisioningOptions? {
        guard vm.configuration.provisioningEnabled, let provisioning = vm.configuration.provisioning else { return nil }

        return createProvisioningOptions(with: provisioning)
    }

    @available(macOS 27.0, *)
    static func createProvisioningOptions(with provisioning: VBMacProvisioningConfiguration) -> VZMacGuestProvisioningOptions {
        let options = VZMacGuestProvisioningOptions()

        options.enablesRemoteLogin = provisioning.enablesRemoteLogin
        options.fullName = provisioning.fullName
        options.username = provisioning.username
        options.password = provisioning.password
        options.logsInAutomatically = provisioning.logsInAutomatically

        return options
    }
}

// MARK: - Configuration Models -> Virtualization

extension VBDisplayDevice {

    var vzDisplay: VZMacGraphicsDisplayConfiguration {
        VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: pixelsPerInch)
    }

}
