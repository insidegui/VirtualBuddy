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

public enum VBGuestType: String, Identifiable, Codable, CaseIterable, ProvidesEmptyPlaceholder {
    public var id: RawValue { rawValue }
    
    case mac
    case linux

    public static var empty: VBGuestType { .mac }
}

public struct VBMacConfiguration: Hashable, Codable {
    
    public enum SupportState: Hashable {
        case supported
        case warnings([String])
        case unsupported([String])
    }

    public static let currentVersion = 0
    @DecodableDefault.Zero public var version = VBMacConfiguration.currentVersion

    @DecodableDefault.FirstCase
    public var systemType: VBGuestType = .mac

    public var hardware = VBMacDevice.default
    public var sharedFolders = [VBSharedFolder]()
    @DecodableDefault.True
    public var guestAdditionsEnabled = true

    @DecodableDefault.False
    public var rosettaSharingEnabled = false

    @DecodableDefault.True public var captureSystemKeys = true

    public var hasSharedFolders: Bool { !sharedFolders.filter(\.isEnabled).isEmpty }

}

// MARK: - Hardware Configuration

/// Configures a disk image that's managed by VirtualBuddy, as opposed to a disk image that the user provides.
/// **Read the note at the top of this file before modifying this**
public struct VBManagedDiskImage: Identifiable, Hashable, Codable {
    public init(id: String = UUID().uuidString, filename: String, size: UInt64, format: VBManagedDiskImage.Format = .sparse) {
        self.id = id
        self.filename = filename
        self.size = size
        self.format = format
    }
    
    public static let defaultBootDiskImageSize: UInt64 = 64 * .storageGigabyte
    public static let minimumBootDiskImageSize: UInt64 = 2 * .storageGigabyte
    public static let maximumBootDiskImageSize: UInt64 = 512 * .storageGigabyte

    public static let minimumExtraDiskImageSize: UInt64 = 1 * .storageGigabyte
    public static let maximumExtraDiskImageSize: UInt64 = 512 * .storageGigabyte
    
    public enum Format: Int, Codable {
        case raw
        case dmg
        case sparse

        var fileExtension: String {
            switch self {
            case .raw:
                return "img"
            case .dmg:
                return "dmg"
            case .sparse:
                return "sparseimage"
            }
        }
    }
    
    public var id: String = UUID().uuidString
    public var filename: String
    public var size: UInt64
    public var format: Format = .sparse
    
    public static var managedBootImage: VBManagedDiskImage {
        VBManagedDiskImage(
            id: "__BOOT__",
            filename: "Disk",
            size: Self.defaultBootDiskImageSize,
            format: .raw
        )
    }
    
    public static var template: VBManagedDiskImage {
        VBManagedDiskImage(
            filename: RandomNameGenerator.shared.newName(),
            size: VBManagedDiskImage.minimumExtraDiskImageSize,
            format: .raw
        )
    }
}

/// Configures a storage device.
/// **Read the note at the top of this file before modifying this**
public struct VBStorageDevice: Identifiable, Hashable, Codable {
    public init(id: String = UUID().uuidString, isBootVolume: Bool, isEnabled: Bool = true, isReadOnly: Bool, isUSBMassStorageDevice: Bool, backing: VBStorageDevice.BackingStore) {
        self.id = id
        self.isBootVolume = isBootVolume
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
        self.isUSBMassStorageDevice = isUSBMassStorageDevice
        self.backing = backing
    }
    
    /// The underlying storage for the device, which currently can be either a custom disk image,
    /// or a disk image managed by VirtualBuddy.
    public enum BackingStore: Hashable, Codable {
        /// Image created and managed by VirtualBuddy.
        case managedImage(VBManagedDiskImage)
        /// Arbitrary image provided by the user, file must exist on disk at the same location
        /// if the image is to be used again in the future.
        case customImage(URL)
    }
    
    public var id: String = UUID().uuidString
    /// `true` for the initial boot volume (Disk.img) that's created by VirtualBuddy.
    public internal(set) var isBootVolume: Bool
    /// Setting to `false` disables the storage device without removing it from the VM.
    @DecodableDefault.True
    public var isEnabled: Bool
    /// `true` if this storage device represents a clone created for a virtual machine save state.
    @DecodableDefault.False
    public var isSavedStateClone: Bool
    /// `true` when the device can't be written to by the VM.
    public var isReadOnly: Bool
    /// `true` when the device represents an external USB mass storage device in the guest OS.
    public var isUSBMassStorageDevice: Bool
    /// The underlying storage for the storage device, which can currently be a disk image managed
    /// by VirtualBuddy, or a custom image provided by the user.
    public var backing: BackingStore
    
    public static var defaultBootDevice: VBStorageDevice {
        VBStorageDevice(
            isBootVolume: true,
            isReadOnly: false,
            isUSBMassStorageDevice: false,
            backing: .managedImage(.managedBootImage)
        )
    }

    public static var template: VBStorageDevice {
        let name = RandomNameGenerator.shared.newName()
        
        let image = VBManagedDiskImage(
            filename: name,
            size: VBManagedDiskImage.minimumExtraDiskImageSize,
            format: .sparse
        )
        
        return VBStorageDevice(
            isBootVolume: false,
            isReadOnly: false,
            isUSBMassStorageDevice: false,
            backing: .managedImage(image)
        )
    }
    
    public var displayName: String {
        guard !isBootVolume else { return "Boot" }
        
        switch backing {
        case .customImage(let url):
            return url.deletingPathExtension().lastPathComponent
        case .managedImage(let image):
            return image.filename
        }
    }
}

/// Configures a display device.
/// **Read the note at the top of this file before modifying this**
public struct VBDisplayDevice: Identifiable, Hashable, Codable {
    public init(id: UUID = UUID(), name: String = "Default", width: Int = 1920, height: Int = 1080, pixelsPerInch: Int = 144, automaticallyReconfiguresDisplay: Bool = false) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.pixelsPerInch = pixelsPerInch
        self.automaticallyReconfiguresDisplay = automaticallyReconfiguresDisplay
    }
    
    public var id = UUID()
    public var name = "Default"
    public var width = 1920
    public var height = 1080
    public var pixelsPerInch = 144
    @DecodableDefault.False public var automaticallyReconfiguresDisplay = false
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

        case mouse
        case trackpad
        
        public var name: String {
            switch self {
            case .mouse: return "Mouse"
            case .trackpad: return "Trackpad"
            }
        }
    }

    public var kind = Kind.mouse
}

/// Configures a keyboard device.
/// **Read the note at the top of this file before modifying this**
public struct VBKeyboardDevice: Hashable, Codable, ProvidesEmptyPlaceholder {
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        case generic
        case mac

        public var name: String {
            switch self {
            case .generic: return "Generic"
            case .mac: return "Mac"
            }
        }
    }

    public var kind = Kind.generic

    public static var empty: VBKeyboardDevice { VBKeyboardDevice(kind: .generic) }
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
    public init(cpuCount: Int, memorySize: UInt64, pointingDevice: VBPointingDevice, keyboardDevice: VBKeyboardDevice, displayDevices: [VBDisplayDevice], networkDevices: [VBNetworkDevice], soundDevices: [VBSoundDevice], storageDevices: [VBStorageDevice], NVRAM: [VBNVRAMVariable] = [VBNVRAMVariable]()) {
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.pointingDevice = pointingDevice
        self.keyboardDevice = keyboardDevice
        self.displayDevices = displayDevices
        self.networkDevices = networkDevices
        self.soundDevices = soundDevices
        self.storageDevices = storageDevices
        self.NVRAM = NVRAM
    }
    
    public var cpuCount: Int
    public var memorySize: UInt64
    public var pointingDevice: VBPointingDevice
    @DecodableDefault.EmptyPlaceholder
    public var keyboardDevice: VBKeyboardDevice
    public var displayDevices: [VBDisplayDevice]
    public var networkDevices: [VBNetworkDevice]
    public var soundDevices: [VBSoundDevice]
    public var NVRAM = [VBNVRAMVariable]()
    
    public var storageDevices: [VBStorageDevice] {
        /// Special handling for migration from previous versions.
        /// Ensures all VMs have the boot storage device set if no storage devices are
        /// present in the loaded configuration.
        get { _storageDevices ?? [.defaultBootDevice] }
        set { _storageDevices = newValue }
    }
    private var _storageDevices: [VBStorageDevice]? = nil
    
    mutating func addMissingBootDeviceIfNeeded() {
        guard _storageDevices == nil else { return }
        _storageDevices = [.defaultBootDevice]
    }
}

// MARK: - Sharing And Other Features

/// Configures a folder that's shared between the host and the guest.
/// **Read the note at the top of this file before modifying this**
public struct VBSharedFolder: Identifiable, Hashable, Codable {
    /// The name the VirtualBuddy share will have in the guest OS.
    ///
    /// This is the name that must be used with the `mount` command, like so:
    /// ```
    /// mkdir -p ~/Desktop/VirtualBuddyShared && mount -t virtiofs VirtualBuddyShared ~/Desktop/VirtualBuddyShared
    /// ```
    public static let virtualBuddyShareName = "VirtualBuddyShared"

    public static let rosettaShareName = "Rosetta"

    public init(id: UUID = UUID(), url: URL, isEnabled: Bool = true, isReadOnly: Bool = false, customMountPointName: String? = nil) {
        self.id = id
        self.url = url
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
        self.customMountPointName = customMountPointName
    }

    public var id = UUID()
    public var name: String { url.lastPathComponent }
    public var url: URL
    @DecodableDefault.True
    public var isEnabled = true
    public var isReadOnly = false
    
    /// A custom name for the folder when mounted in the guest OS.
    public var customMountPointName: String? = nil
    /// The default name for the folder when mounted in the guest OS
    var mountPointName: String { url.lastPathComponent }
    /// The effective name this folder will have when mounted in the guest OS.
    public var effectiveMountPointName: String { customMountPointName ?? mountPointName }
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

        /// Figure out how many "Folder", "Folder 1", "Folder 2", and so on we have in the shared folders collection.
        let conflictingMountPointCount = sharedFolders.filter { $0.mountPointName.trimmingCharacters(in: .decimalDigits.union(.whitespacesAndNewlines)).hasPrefix(url.lastPathComponent) }.count
        
        let customMountPointName: String?
        if conflictingMountPointCount > 0 {
            customMountPointName = "\(url.lastPathComponent) \(conflictingMountPointCount + 1)"
        } else {
            customMountPointName = nil
        }
        
        let folder = VBSharedFolder(url: url, customMountPointName: customMountPointName)

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

    var externalVolumeURL: URL? { url.externalVolumeURL }

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

    func guestType(_ type: VBGuestType) -> Self {
        var mSelf = self
        mSelf.systemType = type
        return mSelf
    }
}

public extension VBMacDevice {
    static var `default`: VBMacDevice {
        VBMacDevice(
            cpuCount: .vb_suggestedVirtualCPUCount,
            memorySize: .vb_suggestedMemorySize,
            pointingDevice: .default,
            keyboardDevice: .default,
            displayDevices: [.default],
            networkDevices: [.default],
            soundDevices: [.default],
            storageDevices: [.defaultBootDevice]
        )
    }
}

public extension VBPointingDevice {
    static var `default`: VBPointingDevice { .init() }
}

public extension VBKeyboardDevice {
    static var `default`: VBKeyboardDevice { .empty }
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

        let resolution = screen.dpi
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
}

// MARK: - Helpers

public extension UInt64 {
    static let storageGigabyte = UInt64(1024 * 1024 * 1024)
    static let storageMegabyte = UInt64(1024 * 1024)
}

public extension VBStorageDevice {
    static func validationError(for name: String) -> String? {
        guard !name.isEmpty else {
            return "Name can't be empty."
        }
        do {
            try VZVirtioBlockDeviceConfiguration.validateBlockDeviceIdentifier(name)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static var hostSupportsUSBMassStorage: Bool { true }

    func diskImageExists(for container: VBStorageDeviceContainer) -> Bool {
        let url = container.diskImageURL(for: self)
        return FileManager.default.fileExists(atPath: url.path)
    }
}

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

    static let minimumDisplayWidth = 800
    
    static let minimumDisplayHeight = 600

    static var maximumDisplayWidth = 6016

    static var maximumDisplayHeight = 3384

    static let displayWidthRange: ClosedRange<Int> = {
        minimumDisplayWidth...maximumDisplayWidth
    }()

    static let displayHeightRange: ClosedRange<Int> = {
        minimumDisplayHeight...maximumDisplayHeight
    }()

    static let minimumDisplayPPI = 72

    static let maximumDisplayPPI = 218

    static let displayPPIRange: ClosedRange<Int> = {
        minimumDisplayPPI...maximumDisplayPPI
    }()

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

public extension NSScreen {
    var dpi: CGSize {
        (deviceDescription[NSDeviceDescriptionKey.resolution] as? CGSize) ?? CGSize(width: 72.0, height: 72.0)
    }
}
