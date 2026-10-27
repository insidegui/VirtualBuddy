import Foundation
import ManagedPreferencesKit
import Testing
import Virtualization
@testable import VirtualCore

struct ManagedDevicePreferencesTests {
    @Test func provisioningRestrictionsAreIndependentAndPreserveSavedSettings() throws {
        guard #available(macOS 27.0, *) else { return }
        let provisioning = VBMacProvisioningConfiguration(
            enablesRemoteLogin: true, logsInAutomatically: true,
            fullName: "Example User", username: "example",
            password: KeychainReference(service: "VirtualBuddyTests", account: UUID().uuidString)
        )
        let saved = provisioning
        for (values, remoteLogin, automaticLogin) in [
            ([:], true, true),
            (["DisableProvisioningRemoteLogin": true], false, true),
            (["DisableProvisioningAutomaticLogin": true], true, false),
            (["DisableProvisioningRemoteLogin": true, "DisableProvisioningAutomaticLogin": true], false, false)
        ] as [([String: Any], Bool, Bool)] {
            let options = MacOSVirtualMachineConfigurationHelper.createProvisioningOptions(with: provisioning, preferences: reader(values))
            #expect(options.enablesRemoteLogin == remoteLogin)
            #expect(options.logsInAutomatically == automaticLogin)
            #expect(options.fullName == provisioning.fullName)
            #expect(options.username == provisioning.username)
        }
        #expect(provisioning == saved)
    }

    @Test func restrictedBridgeDoesNotResolveHostInterfaceOrChangeSavedSelection() throws {
        let device = VBNetworkDevice(id: "unavailable-interface", kind: .bridge)
        let saved = device
        #expect(try device.makeAttachment(preferences: reader(["DisableBridgedNetworking": true])) == nil)
        #expect(device == saved)
        #expect(throws: (any Error).self) {
            try device.makeAttachment(preferences: reader([:]))
        }
    }

    @Test func bridgeRestrictionPreservesNAT() throws {
        let device = VBNetworkDevice(kind: .NAT)
        #expect(try device.makeAttachment(preferences: reader(["DisableBridgedNetworking": true])) is VZNATNetworkDeviceAttachment)
    }

    @Test func microphoneRestrictionProducesSilenceAndPreservesOutputAndTopology() throws {
        let device = VBSoundDevice()
        let saved = device
        let restricted = try #require(device.makeConfiguration(preferences: reader(["DisableMicrophoneInput": true])) as? VZVirtioSoundDeviceConfiguration)
        let normal = try #require(device.makeConfiguration(preferences: reader([:])) as? VZVirtioSoundDeviceConfiguration)
        #expect(restricted.streams.count == normal.streams.count)
        let input = try #require(restricted.streams.first as? VZVirtioSoundDeviceInputStreamConfiguration)
        #expect(input.source == nil)
        let output = try #require(restricted.streams.last as? VZVirtioSoundDeviceOutputStreamConfiguration)
        #expect(output.sink is VZHostAudioOutputStreamSink)
        #expect((normal.streams.first as? VZVirtioSoundDeviceInputStreamConfiguration)?.source is VZHostAudioInputStreamSource)
        #expect(device == saved)
    }

    @Test func existingMicrophoneConfigurationCannotResumeUnderRestriction() throws {
        let configuration = VZVirtualMachineConfiguration()
        let device = VBSoundDevice()
        configuration.audioDevices = [device.makeConfiguration(preferences: reader([:]))]
        #expect(throws: (any Error).self) {
            try configuration.validateMicrophonePolicy(preferences: reader(["DisableMicrophoneInput": true]))
        }
        try configuration.validateMicrophonePolicy(preferences: reader([:]))
        configuration.audioDevices = [device.makeConfiguration(preferences: reader(["DisableMicrophoneInput": true]))]
        try configuration.validateMicrophonePolicy(preferences: reader(["DisableMicrophoneInput": true]))
    }

    @Test func guestAppPolicyOmitsInstallerWithoutChangingGuestConfiguration() async throws {
        var configuration = VBMacConfiguration()
        configuration.guestAdditionsEnabled = true
        let saved = configuration
        let disk = try await VZVirtioBlockDeviceConfiguration.guestAdditionsDisk(
            for: configuration, preferences: reader(["DisableGuestApp": true])
        )
        #expect(disk == nil)
        #expect(configuration == saved)
        #expect(configuration.guestAdditionsEnabled)
    }

    @Test func allRestrictionsAreDocumentedAndDefaultToUnrestricted() throws {
        let schema = VirtualBuddyManagedPreferences.schema
        let expectedKeys: Set<String> = [
            "DisableSharedFolders", "DisableGuestApp", "DisableUSBPassthrough",
            "DisableBridgedNetworking", "DisableMicrophoneInput",
            "DisableProvisioningRemoteLogin", "DisableProvisioningAutomaticLogin"
        ]
        #expect(Set(schema.preferences.map(\.key)) == expectedKeys)
        let declarations: [VirtualBuddyManagedPreferences.Preference<Bool>] = [
            .disableSharedFolders, .disableGuestApp, .disableUSBPassthrough,
            .disableBridgedNetworking, .disableMicrophoneInput,
            .disableProvisioningRemoteLogin, .disableProvisioningAutomaticLogin
        ]
        for preference in declarations {
            for value: Any? in [nil, false, "true", 1] {
                let values = value.map { [preference.key: $0] } ?? [:]
                #expect(reader(values).value(for: preference, default: true) == false)
            }
            #expect(reader([preference.key: true]).value(for: preference, default: false))
        }
        let manifest = try #require(PropertyListSerialization.propertyList(from: schema.profileManifestData(), format: nil) as? [String: Any])
        let subkeys = try #require(manifest["pfm_subkeys"] as? [[String: Any]])
        for key in expectedKeys {
            let entry = try #require(subkeys.first { $0["pfm_name"] as? String == key })
            #expect(entry["pfm_default"] as? Bool == false)
            #expect(entry["pfm_type"] as? String == "boolean")
        }
    }

    private func reader(_ values: [String: Any]) -> ManagedPreferenceReader<VirtualBuddyManagedPreferences> {
        VirtualBuddyManagedPreferences.schema.reader(store: PolicyStore(values: values))
    }

    private struct PolicyStore: ManagedPreferenceStore {
        var values: [String: Any]
        func value(forKey key: String, domain: String) -> Any? { values[key] }
        func valueIsForced(forKey key: String, domain: String) -> Bool { values[key] != nil }
    }
}
