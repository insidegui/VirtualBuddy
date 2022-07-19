//
//  ConfigurationModels.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 17/07/22.
//

import Foundation
import SystemConfiguration

/**
 ## Note to contributors:

 Care must be taken when changing any of the structs in this file that conform to `Codable`,
 since users may have VMs configured using older versions of the structs. Failure to decode the configuration
 after updates to how it's stored can result in data loss.

 In order to keep backwards-compatibility for new properties without having to make everything optional,
 the `@DecodableDefault` property wrapper can be used.
 */

public struct VBMacConfiguration: Hashable, Codable {

    public static let currentVersion = 0
    @DecodableDefault.Zero public var version = VBMacConfiguration.currentVersion

    public var hardware = VBMacDevice.default
    public var sharedFolders = [VBSharedFolder]()
    @DecodableDefault.False
    public var sharedClipboardEnabled = false

    @DecodableDefault.True public var captureSystemKeys = true

}

// MARK: - Hardware Configuration

/// Configures a display device.
/// **Read the note at the top of this file before modifying this**
public struct VBDisplayDevice: Identifiable, Hashable, Codable {
    public init(id: UUID = UUID(), name: String = "Default", width: Int = 1920, height: Int = 1080, pixelsPerInch: Int = 144) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.pixelsPerInch = pixelsPerInch
    }
    
    public var id = UUID()
    public var name = "Default"
    public var width = 1920
    public var height = 1080
    public var pixelsPerInch = 144
}

/// Configures a network device.
/// **Read the note at the top of this file before modifying this**
public struct VBNetworkDevice: Identifiable, Hashable, Codable {
    public init(id: String = "Default", name: String = "Default", kind: VBNetworkDevice.Kind = Kind.NAT, macAddress: String = VZMACAddress.randomLocallyAdministered().string.uppercased()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.macAddress = macAddress
    }
    
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        case NAT
        case bridge
        
        public var name: String {
            switch self {
            case .NAT: return "NAT"
            case .bridge: return "Bridge"
            }
        }
    }

    public var id = "Default"
    public var name = "Default"
    public var kind = Kind.NAT
    public var macAddress = VZMACAddress.randomLocallyAdministered().string.uppercased()
}

/// Configures a pointing device, such as a mouse or trackpad.
/// **Read the note at the top of this file before modifying this**
public struct VBPointingDevice: Hashable, Codable {
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        public var warning: String? {
            guard self == .trackpad else { return nil }
            return "Trackpad is only recognized by VMs running macOS 13 and later."
        }

        public var isSupportedByGuest: Bool {
            if #available(macOS 13.0, *) {
                return true
            } else {
                return self == .mouse
            }
        }

        case mouse
        case trackpad
    }

    public var kind = Kind.mouse
}

/// Configures sound input/output.
/// **Read the note at the top of this file before modifying this**
public struct VBSoundDevice: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name = "Default"
    public var enableOutput = true
    public var enableInput = true
}

/// Describes a Mac VM with its associated hardware configuration.
/// **Read the note at the top of this file before modifying this**
public struct VBMacDevice: Hashable, Codable {
    public var cpuCount: Int
    public var memorySize: UInt64
    public var pointingDevice: VBPointingDevice
    public var displayDevices: [VBDisplayDevice]
    public var networkDevices: [VBNetworkDevice]
    public var soundDevices: [VBSoundDevice]
    public var NVRAM = [VBNVRAMVariable]()
}

// MARK: - Sharing And Other Features

/// Configures a folder that's shared between the host and the guest.
/// **Read the note at the top of this file before modifying this**
public struct VBSharedFolder: Identifiable, Hashable, Codable {
    public init(id: UUID = UUID(), url: URL, isEnabled: Bool = true, isReadOnly: Bool = true) {
        self.id = id
        self.url = url
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
    }

    public var id = UUID()
    public var name: String { url.lastPathComponent }
    public var url: URL
    @DecodableDefault.True
    public var isEnabled = true
    public var isReadOnly = true
}

public extension VBMacConfiguration {
    func hasSharedFolder(with url: URL) -> Bool {
        sharedFolders.contains(where: { $0.url.path == url.path })
    }

    @discardableResult
    mutating func addSharedFolder(with url: URL) throws -> VBSharedFolder {
        guard url.isReadableDirectory else {
            throw Failure("VirtualBuddy couldn't access the selected location, or it is not a directory.")
        }

        guard !hasSharedFolder(with: url) else {
            throw Failure("That directory is already in the shared folders.")
        }

        let folder = VBSharedFolder(url: url)

        sharedFolders.append(folder)

        return folder
    }

    mutating func removeSharedFolders(with identifiers: Set<VBSharedFolder.ID>) {
        sharedFolders.removeAll(where: { identifiers.contains($0.id) })
    }
    
    func hasSharedFolders(inVolume volumeURL: URL) -> Bool {
        sharedFolders.contains(where: { $0.externalVolumeURL == volumeURL })
    }
}

public extension VBSharedFolder {
    var shortName: String {
        if url.path.hasPrefix(NSHomeDirectory()) {
            return url.lastPathComponent
        } else {
            return url.path
        }
    }

    var shortNameForDialogs: String { url.lastPathComponent }

    var externalVolumeURL: URL? {
        guard (try? url.resourceValues(forKeys: [.volumeIsInternalKey]))?.volumeIsInternal != true else { return nil }
        return try? url.resourceValues(forKeys: [.volumeURLKey]).volume
    }

    var errorMessage: String? {
        guard !url.isReadableDirectory else { return nil }
        if let externalVolumeURL, !externalVolumeURL.isReadableDirectory {
            return "This directory is in a removable volume that's not currently available."
        } else {
            return "This directory doesn't exist, or VirtualBuddy can't read it right now."
        }
    }

    var isAvailable: Bool { url.isReadableDirectory }
}

public extension URL {
    var isReadableDirectory: Bool {
        var isDir = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return true
    }
}



// MARK: - Default Devices

public extension VBMacConfiguration {
    static var `default`: VBMacConfiguration { .init() }
}

public extension VBMacDevice {
    static var `default`: VBMacDevice {
        VBMacDevice(
            cpuCount: .vb_suggestedVirtualCPUCount,
            memorySize: .vb_suggestedMemorySize,
            pointingDevice: .default,
            displayDevices: [.default],
            networkDevices: [.default],
            soundDevices: [.default]
        )
    }
}

public extension VBPointingDevice {
    static var `default`: VBPointingDevice { .init() }
}

public extension VBNetworkDevice {
    static var `default`: VBNetworkDevice { .init() }
}

public extension VBSoundDevice {
    static var `default`: VBSoundDevice { .init() }
}

public extension VBDisplayDevice {
    static var `default`: VBDisplayDevice { .matchHost }

    static var fallback: VBDisplayDevice { .init() }

    static var matchHost: VBDisplayDevice {
        guard let screen = NSScreen.main else { return .fallback }

        guard let resolution = screen.deviceDescription[.resolution] as? NSSize else { return .fallback }
        guard let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }

        let pointHeight = size.height - screen.safeAreaInsets.top

        return VBDisplayDevice(
            id: UUID(),
            name: ProcessInfo.processInfo.vb_hostName,
            width: Int(size.width * screen.backingScaleFactor),
            height: Int(pointHeight * screen.backingScaleFactor),
            pixelsPerInch: Int(resolution.width)
        )
    }

    static var sizeToFit: VBDisplayDevice {
        guard let screen = NSScreen.main,
              let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }

        let reference = VZMacGraphicsDisplayConfiguration(for: screen, sizeInPoints: size)

        return VBDisplayDevice(
            id: UUID(),
            name: ProcessInfo.processInfo.vb_hostName,
            width: reference.widthInPixels,
            height: reference.heightInPixels,
            pixelsPerInch: reference.pixelsPerInch
        )
    }
}

// MARK: - Presets

public struct VBDisplayPreset: Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var device: VBDisplayDevice
    public var warning: String? = nil
    public var isAvailable = true
}

public extension VBDisplayPreset {
    static var presets: [VBDisplayPreset] {
        [
            VBDisplayPreset(name: "Full HD", device: .init(name: "1920x1080@144", width: 1920, height: 1080, pixelsPerInch: 144)),
            VBDisplayPreset(name: "4.5K Retina", device: .init(name: "4480x2520", width: 4480, height: 2520, pixelsPerInch: 218)),
            // This preset is only relevant for displays with a notch.
            VBDisplayPreset(name: "Match \"\(ProcessInfo.processInfo.vb_mainDisplayName)\"", device: .matchHost, warning: "If things look small in the VM after boot, go to System Preferences and select a HiDPI scaled reslution for the display.", isAvailable: ProcessInfo.processInfo.vb_mainDisplayHasNotch),
            VBDisplayPreset(name: "Size to fit in \"\(ProcessInfo.processInfo.vb_mainDisplayName)\"", device: .sizeToFit)
        ]
    }
    
    static var availablePresets: [VBDisplayPreset] { presets.filter(\.isAvailable) }
}

public struct VBNetworkDeviceBridgeInterface: Identifiable {
    public var id: String
    public var name: String
    
    init(_ interface: VZBridgedNetworkInterface) {
        self.id = interface.identifier
        self.name = interface.localizedDisplayName ?? interface.identifier
    }
}

public extension VBNetworkDevice {
    static var defaultBridgeInterfaceID: String? {
        VZBridgedNetworkInterface.networkInterfaces.first?.identifier
    }
    
    static var bridgeInterfaces: [VBNetworkDeviceBridgeInterface] {
        VZBridgedNetworkInterface.networkInterfaces.map(VBNetworkDeviceBridgeInterface.init)
    }
    
    static var appSupportsBridgedNetworking: Bool {
        NSApplication.shared.hasEntitlement("com.apple.vm.networking")
    }
}

public extension VBMacConfiguration {
    
    func validate(for model: VBVirtualMachine) async -> String? {
        var tempModel = model
        tempModel.configuration = self
        
        do {
            let config = try await VMInstance.makeConfiguration(for: tempModel)
            
            try config.validate()
            
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static let isNativeClipboardSharingSupported: Bool = {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }()

    static let clipboardSharingNotice: String = {
        let guestAppInfo = "To use clipboard sync with previous versions of macOS, you can use the VirtualBuddyGuest app."

        if isNativeClipboardSharingSupported {
            return "Clipboard sync requires the virtual machine to be running macOS 13 or later. \(guestAppInfo)"
        } else {
            return "Clipboard sync requires macOS 13 or later. \(guestAppInfo)"
        }
    }()
    
}

// MARK: - Helpers

public extension VBNetworkDevice {
    static func validateMAC(_ address: String) -> Bool {
        VZMACAddress(string: address) != nil
    }
}

public extension VBMacDevice {
    static let minimumCPUCount: Int = VZVirtualMachineConfiguration.minimumAllowedCPUCount

    static let maximumCPUCount: Int = {
        min(ProcessInfo.processInfo.processorCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)
    }()

    static let virtualCPUCountRange: ClosedRange<Int> = {
        minimumCPUCount...maximumCPUCount
    }()

    static let minimumMemorySizeInGigabytes = 2

    static let maximumMemorySizeInGigabytes: Int = {
        let value = Swift.min(ProcessInfo.processInfo.physicalMemory, VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        return Int(value / 1024 / 1024 / 1024)
    }()

    static let memorySizeRangeInGigabytes: ClosedRange<Int> = {
        minimumMemorySizeInGigabytes...maximumMemorySizeInGigabytes
    }()
}

public extension VBDisplayDevice {

    static let minimumDisplayDimension = 800

    static var maximumDisplayWidth = 6016

    static var maximumDisplayHeight = 3384

    static let displayWidthRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayWidth
    }()

    static let displayHeightRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayHeight
    }()

    static let minimumDisplayPPI = 80

    static let maximumDisplayPPI = 218

    static let displayPPIRange: ClosedRange<Int> = {
        minimumDisplayPPI...maximumDisplayPPI
    }()

}

public extension VBMacConfiguration {

    var generalSummary: String {
        "\(hardware.cpuCount) CPUs / \(hardware.memorySize / 1024 / 1024 / 1024) GB"
    }

    var displaySummary: String {
        guard let display = hardware.displayDevices.first else { return "No Displays" }
        return "\(display.width)x\(display.height)x\(display.pixelsPerInch)"
    }

    var soundSummary: String {
        guard let sound = hardware.soundDevices.first else { return "No Sound" }
        return sound.enableInput ? "Input / Output" : "Output Only"
    }

    var sharingSummary: String {
        let foldersSum: String
        if sharedFolders.count > 1 {
            foldersSum = "\(sharedFolders.count) Folders"
        } else if sharedFolders.isEmpty {
            foldersSum = ""
        } else {
            foldersSum = "One Folder"
        }

        if sharedClipboardEnabled {
            if foldersSum.isEmpty {
                return "Clipboard"
            } else {
                return "Clipboard / \(foldersSum)"
            }
        } else {
            return foldersSum.isEmpty ? "None" : foldersSum
        }
    }

    var networkSummary: String {
        guard let network = hardware.networkDevices.first else { return "No Network" }
        return network.kind.name
    }

}

extension Int {

    static let vb_suggestedVirtualCPUCount: Int = {
        let totalAvailableCPUs = ProcessInfo.processInfo.processorCount

        var virtualCPUCount = totalAvailableCPUs <= 1 ? 1 : totalAvailableCPUs / 2
        virtualCPUCount = Swift.max(virtualCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        virtualCPUCount = Swift.min(virtualCPUCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)

        return virtualCPUCount
    }()

}

extension UInt64 {

    static let vb_suggestedMemorySize: UInt64 = {
        let hostMemory = ProcessInfo.processInfo.physicalMemory
        var memorySize = hostMemory / 2
        memorySize = Swift.max(memorySize, VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        memorySize = Swift.min(memorySize, VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        return memorySize
    }()

}

public extension ProcessInfo {
    var vb_hostName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as? String ?? "This Mac"
    }
    
    var vb_mainDisplayName: String {
        guard let screen = NSScreen.main else { return "\(vb_hostName)" }
        return screen.localizedName
    }
    
    var vb_mainDisplayHasNotch: Bool { NSScreen.main?.auxiliaryTopLeftArea != nil }
}
