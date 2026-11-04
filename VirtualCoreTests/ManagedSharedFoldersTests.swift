import Foundation
import ManagedPreferencesKit
import Testing
import Virtualization
@testable import VirtualCore

struct ManagedSharedFoldersTests {
    @Test(arguments: [VBGuestType.mac, .linux])
    func disabledPolicyPreservesMappingsWithoutExposingDirectories(guestType: VBGuestType) throws {
        var configuration = VBMacConfiguration()
        configuration.systemType = guestType
        configuration.rosettaSharingEnabled = false
        configuration.sharedFolders = [VBSharedFolder(url: FileManager.default.temporaryDirectory)]
        let savedConfiguration = configuration

        let devices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(true))
        let device = try #require(devices.first as? VZVirtioFileSystemDeviceConfiguration)
        let share = try #require(device.share as? VZMultipleDirectoryShare)

        #expect(devices.count == 1)
        #expect(device.tag == VBSharedFolder.virtualBuddyShareName)
        #expect(share.directories.isEmpty)
        #expect(configuration == savedConfiguration)
    }

    @Test func absentFalseAndInvalidPolicyKeepExistingBehavior() throws {
        let directory = FileManager.default.temporaryDirectory
        var configuration = VBMacConfiguration()
        configuration.sharedFolders = [
            VBSharedFolder(url: directory, isReadOnly: true, customMountPointName: "Documents")
        ]
        var disabledFolder = VBSharedFolder(url: directory, customMountPointName: "Disabled")
        disabledFolder.isEnabled = false
        configuration.sharedFolders.append(disabledFolder)

        for rawValue: Any? in [nil, false, "true", 1] {
            let devices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(rawValue))
            let device = try #require(devices.first as? VZVirtioFileSystemDeviceConfiguration)
            let share = try #require(device.share as? VZMultipleDirectoryShare)
            #expect(share.directories.count == 1)
            let folder = try #require(share.directories["Documents"])
            #expect(folder.url == directory)
            #expect(folder.isReadOnly)
        }
    }

    @Test func removingPolicyRestoresSavedMappingsOnNextConfiguration() throws {
        var configuration = VBMacConfiguration()
        configuration.sharedFolders = [VBSharedFolder(url: FileManager.default.temporaryDirectory)]

        for disabled in [false, true, false] {
            let devices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(disabled))
            let device = try #require(devices.first as? VZVirtioFileSystemDeviceConfiguration)
            let share = try #require(device.share as? VZMultipleDirectoryShare)
            #expect(share.directories.count == (disabled ? 0 : 1))
        }
        #expect(configuration.sharedFolders.count == 1)
    }

    @Test(.enabled(if: VBMacConfiguration.rosettaInstalled()))
    func policyDoesNotDisableRosetta() throws {
        var configuration = VBMacConfiguration()
        configuration.systemType = .linux
        configuration.rosettaSharingEnabled = true

        let devices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(true))
        let rosetta = try #require(devices.compactMap { $0 as? VZVirtioFileSystemDeviceConfiguration }
            .first { $0.tag == VBSharedFolder.rosettaShareName })
        #expect(rosetta.share is VZLinuxRosettaDirectoryShare)
    }

    @Test func replacingMappingsAppliesAddRemoveAndReadOnlyChanges() throws {
        let directory = FileManager.default.temporaryDirectory
        var configuration = VBMacConfiguration()
        configuration.sharedFolders = [VBSharedFolder(url: directory, customMountPointName: "Original")]
        let originalShare = try configuration.makeSharedFoldersShare(preferences: reader(false))

        configuration.sharedFolders[0].isReadOnly = true
        configuration.sharedFolders.append(VBSharedFolder(url: directory, customMountPointName: "Added"))
        let updatedShare = try configuration.makeSharedFoldersShare(preferences: reader(false))
        #expect(updatedShare.directories.count == 2)
        #expect(updatedShare.directories["Original"]?.isReadOnly == true)
        #expect(updatedShare.directories["Added"]?.isReadOnly == false)
        #expect(originalShare.directories["Original"]?.isReadOnly == false)

        configuration.sharedFolders.removeFirst()
        let removedShare = try configuration.makeSharedFoldersShare(preferences: reader(false))
        #expect(removedShare.directories["Original"] == nil)
        #expect(removedShare.directories["Added"] != nil)

        configuration.sharedFolders[0].isEnabled = false
        #expect(try configuration.makeSharedFoldersShare(preferences: reader(false)).directories.isEmpty)
        configuration.sharedFolders.removeAll()
        #expect(try configuration.makeSharedFoldersShare(preferences: reader(false)).directories.isEmpty)
    }

    @Test func invalidOrDuplicateMountNamesFailWithoutReplacingThePreviousShare() throws {
        var configuration = VBMacConfiguration()
        configuration.sharedFolders = [VBSharedFolder(url: FileManager.default.temporaryDirectory, customMountPointName: "Valid")]
        let share = try configuration.makeSharedFoldersShare(preferences: reader(false))

        configuration.sharedFolders[0].customMountPointName = "invalid/name"
        #expect(throws: (any Error).self) {
            try configuration.makeSharedFoldersShare(preferences: reader(false))
        }
        configuration.sharedFolders[0].customMountPointName = "Valid"
        configuration.sharedFolders.append(VBSharedFolder(url: FileManager.default.temporaryDirectory, customMountPointName: "Valid"))
        #expect(throws: (any Error).self) {
            try configuration.makeSharedFoldersShare(preferences: reader(false))
        }
        #expect(share.directories.count == 1)
        #expect(share.directories["Valid"] != nil)
    }

    @Test func folderChangesAndPolicyDoNotChangeSavedSessionTopology() throws {
        var configuration = VBMacConfiguration()
        configuration.rosettaSharingEnabled = false
        let initial = VZVirtualMachineConfiguration()
        initial.directorySharingDevices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(false))
        let topology = SavedSessionRuntimeDescription(configuration: initial)

        configuration.sharedFolders = [VBSharedFolder(url: FileManager.default.temporaryDirectory, isReadOnly: true)]
        for disabled in [false, true, false] {
            let updated = VZVirtualMachineConfiguration()
            updated.directorySharingDevices = try configuration.makeSharedFoldersFileSystemDevices(preferences: reader(disabled))
            #expect(topology.firstDifference(from: SavedSessionRuntimeDescription(configuration: updated)) == nil)
            let share = try configuration.makeSharedFoldersShare(preferences: reader(disabled))
            #expect(share.directories.count == (disabled ? 0 : 1))
            #expect(configuration.sharedFolders[0].isReadOnly)
        }
    }

    @Test func administratorDocumentationExportsTheImplementedPolicy() throws {
        let schema = VirtualBuddyManagedPreferences.schema
        let markdown = schema.markdownDocumentation()
        #expect(markdown.contains("DisableSharedFolders"))
        #expect(markdown.contains("codes.rambo.VirtualBuddy"))
        #expect(!markdown.contains("AllowedNetworkModes"))

        let data = try schema.profileManifestData()
        let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(manifest["pfm_domain"] as? String == "codes.rambo.VirtualBuddy")
        let subkeys = try #require(manifest["pfm_subkeys"] as? [[String: Any]])
        let preference = try #require(subkeys.first { $0["pfm_name"] as? String == "DisableSharedFolders" })
        #expect(preference["pfm_type"] as? String == "boolean")
        #expect(preference["pfm_default"] as? Bool == false)
    }

    private func reader(_ value: Any?) -> ManagedPreferenceReader<VirtualBuddyManagedPreferences> {
        VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(value: value))
    }

    private struct PolicyStore: ManagedPreferenceStore {
        var value: Any?

        func value(forKey key: String, domain: String) -> Any? { value }
        func valueIsForced(forKey key: String, domain: String) -> Bool { value != nil }
    }
}
