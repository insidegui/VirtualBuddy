import Foundation
import Testing
import Virtualization
@testable import VirtualCore

struct GuestIsolationConfigurationTests {
    @Test func olderConfigurationsKeepClipboardSharingEnabled() throws {
        let data = try PropertyListEncoder().encode(VBMacConfiguration())
        var properties = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        properties.removeValue(forKey: "clipboardSharingEnabled")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)

        let configuration = try PropertyListDecoder().decode(VBMacConfiguration.self, from: legacyData)

        #expect(configuration.clipboardSharingEnabled)
    }

    @Test(arguments: [false, true])
    func clipboardSharingPreferencePersists(enabled: Bool) throws {
        var configuration = VBMacConfiguration()
        configuration.systemType = .linux
        configuration.clipboardSharingEnabled = enabled

        let data = try PropertyListEncoder().encode(configuration)
        let decoded = try PropertyListDecoder().decode(VBMacConfiguration.self, from: data)

        #expect(decoded == configuration)
    }

    @Test(arguments: [false, true])
    func linuxClipboardChannelIsIndependentOfGuestAppAndRosetta(enabled: Bool) throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)
        var vm = try VBVirtualMachine(creatingLinuxMachineAt: bundleURL)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        vm.configuration.clipboardSharingEnabled = enabled
        for guestAppEnabled in [false, true] {
            for rosettaEnabled in [false, true] {
                vm.configuration.guestAdditionsEnabled = guestAppEnabled
                vm.configuration.rosettaSharingEnabled = rosettaEnabled
                let console = LinuxVirtualMachineConfigurationHelper(vm: vm)
                    .createSpiceAgentConsoleDeviceConfiguration()

                if enabled {
                    let device = try #require(console)
                    let port = try #require(device.ports[0])
                    let attachment = try #require(port.attachment as? VZSpiceAgentPortAttachment)
                    #expect(port.name == VZSpiceAgentPortAttachment.spiceAgentPortName)
                    #expect(attachment.sharesClipboard)
                } else {
                    #expect(console == nil)
                }
            }
        }
    }
}
