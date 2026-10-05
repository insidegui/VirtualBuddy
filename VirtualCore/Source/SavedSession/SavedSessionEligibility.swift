import Foundation
import Virtualization

/// Determines whether a virtual machine can have its session saved and resumed.
public struct SavedSessionEligibility: Hashable, Sendable {
    public enum Issue: Hashable, Sendable {
        case unsupportedGuest
        case installationIncomplete
        case externalDiskImage(String)
        case volumeDoesNotSupportCloning
        case specialBootMode(String)
        case usbDeviceAttached
        case runtimeConfigurationUnsupported(String)

        public var explanation: String {
            switch self {
            case .unsupportedGuest:
                "Saving the session is only available for macOS virtual machines."
            case .installationIncomplete:
                "Saving the session isn't available until the operating system has been installed."
            case .externalDiskImage(let name):
                "The disk image \"\(name)\" is stored outside of the virtual machine. Copy it into the virtual machine in its settings to be able to save its session."
            case .volumeDoesNotSupportCloning:
                "The volume where this virtual machine is stored doesn't support file cloning, which is required to save its session."
            case .specialBootMode(let mode):
                "Saving the session isn't available when starting up in \(mode)."
            case .usbDeviceAttached:
                "Saving the session isn't available while a USB device is attached to the virtual machine. Detach it to save the session."
            case .runtimeConfigurationUnsupported(let reason):
                "This virtual machine's configuration doesn't support saving its session. \(reason)"
            }
        }
    }

    public var issues: [Issue]

    public var isSupported: Bool { issues.isEmpty }

    public var primaryIssue: Issue? { issues.first }

    /// `false` for virtual machines that can't have their state saved at all, such as Linux guests.
    /// Nothing about saving should be shown for those.
    public var isApplicable: Bool { issues != [.unsupportedGuest] }

    /// The reason to give the user when saving isn't available, or `nil` when saving isn't something that applies to the
    /// virtual machine at all (such as Linux guests), in which case saving must not be mentioned.
    public var explanationForUser: String? {
        guard isApplicable else { return nil }
        return primaryIssue?.explanation ?? "Saving isn’t available for this virtual machine."
    }

    public static let supported = SavedSessionEligibility(issues: [])

    public init(issues: [Issue]) {
        self.issues = issues
    }
}

// MARK: - Evaluation

extension SavedSessionEligibility {
    /// Checks everything that can be known about a virtual machine without constructing its runtime configuration.
    ///
    /// - Parameter supportsCloning: Whether the volume of the virtual machine supports file cloning. Looked up when `nil`.
    static func evaluate(model: VBVirtualMachine, options: VMSessionOptions, supportsCloning: Bool? = nil) -> SavedSessionEligibility {
        var issues = [Issue]()

        guard model.configuration.systemType.supportsStateRestoration else {
            return SavedSessionEligibility(issues: [.unsupportedGuest])
        }

        if model.needsInstall || !model.metadata.installFinished {
            issues.append(.installationIncomplete)
        }

        if options.bootInRecoveryMode {
            issues.append(.specialBootMode("recovery mode"))
        }
        if options.bootInDFUMode {
            issues.append(.specialBootMode("DFU mode"))
        }
        if options.bootOnInstallDevice {
            issues.append(.specialBootMode("the install device"))
        }

        for device in model.configuration.hardware.storageDevices where device.isEnabled {
            if case .customImage = device.backing {
                issues.append(.externalDiskImage(device.displayName))
            }
        }

        if !(supportsCloning ?? model.bundleURL.volumeSupportsFileCloning) {
            issues.append(.volumeDoesNotSupportCloning)
        }

        return SavedSessionEligibility(issues: issues)
    }

    /// Validates the runtime configuration that was actually used to construct the virtual machine.
    static func evaluate(runtimeConfiguration: VZVirtualMachineConfiguration) -> SavedSessionEligibility {
        do {
            try runtimeConfiguration.validateSaveRestoreSupport()
            return .supported
        } catch {
            return SavedSessionEligibility(issues: [.runtimeConfigurationUnsupported(error.localizedDescription)])
        }
    }

    func merging(_ other: SavedSessionEligibility) -> SavedSessionEligibility {
        var merged = issues
        for issue in other.issues where !merged.contains(issue) {
            merged.append(issue)
        }
        return SavedSessionEligibility(issues: merged)
    }
}

extension URL {
    /// Whether the volume that contains this URL supports copy-on-write file cloning.
    ///
    /// This is determined at the location of the item itself because the library's volume
    /// says nothing about a virtual machine that was moved somewhere else.
    var volumeSupportsFileCloning: Bool {
        #if DEBUG
        guard !UserDefaults.standard.bool(forKey: "VBSimulateNonAPFSVolume") else { return false }
        #endif

        var url = self
        /// The bundle may not exist yet when asking for a volume, so walk up to the nearest existing ancestor.
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
            url = url.deletingLastPathComponent()
        }

        return (try? url.resourceValues(forKeys: [.volumeSupportsFileCloningKey]))?.volumeSupportsFileCloning == true
    }
}

// MARK: - Runtime Description

/// Describes the topology of the configuration that was used to construct a running virtual machine.
///
/// The description is stored with a saved session and compared against the configuration that would be used
/// to restore it. A saved memory image is only valid for the exact device topology it was created with, so any
/// difference (for example, caused by an app update changing a default device) prevents the session from being resumed.
/// Only structure is described. Live resources such as the contents of shared folders and whether the microphone is
/// connected to the host are deliberately excluded because they're allowed to change between sessions.
struct SavedSessionRuntimeDescription: Codable, Hashable, Sendable {
    struct Storage: Codable, Hashable, Sendable {
        var deviceClass: String
        var isReadOnly: Bool
    }

    struct Network: Codable, Hashable, Sendable {
        var deviceClass: String
        var macAddress: String
    }

    struct Display: Codable, Hashable, Sendable {
        var width: Int
        var height: Int
        var pixelsPerInch: Int
    }

    struct Audio: Codable, Hashable, Sendable {
        var hasInput: Bool
        var hasOutput: Bool
    }

    var platformClass: String
    var bootLoaderClass: String
    var cpuCount: Int
    var memorySize: UInt64
    var storage: [Storage]
    var network: [Network]
    var graphicsClasses: [String]
    var displays: [Display]
    var audio: [Audio]
    var directorySharingTags: [String]
    var socketDeviceCount: Int
    var usbControllerClasses: [String]
    var entropyDeviceCount: Int
    var consoleDeviceClasses: [String]
    var keyboardClasses: [String]
    var pointingDeviceClasses: [String]

    init(configuration c: VZVirtualMachineConfiguration) {
        func className(_ object: AnyObject) -> String { NSStringFromClass(type(of: object)) }

        platformClass = className(c.platform)
        bootLoaderClass = c.bootLoader.map { className($0) } ?? ""
        cpuCount = c.cpuCount
        memorySize = c.memorySize

        storage = c.storageDevices.map { device in
            Storage(
                deviceClass: className(device),
                isReadOnly: (device.attachment as? VZDiskImageStorageDeviceAttachment)?.isReadOnly ?? false
            )
        }

        network = c.networkDevices.map { device in
            Network(
                deviceClass: className(device),
                macAddress: ((device as? VZVirtioNetworkDeviceConfiguration)?.macAddress.string ?? "").uppercased()
            )
        }

        graphicsClasses = c.graphicsDevices.map { className($0) }
        displays = c.graphicsDevices
            .compactMap { $0 as? VZMacGraphicsDeviceConfiguration }
            .flatMap(\.displays)
            .map { Display(width: $0.widthInPixels, height: $0.heightInPixels, pixelsPerInch: $0.pixelsPerInch) }

        audio = c.audioDevices
            .compactMap { $0 as? VZVirtioSoundDeviceConfiguration }
            .map { device in
                Audio(
                    hasInput: device.streams.contains { $0 is VZVirtioSoundDeviceInputStreamConfiguration },
                    hasOutput: device.streams.contains { $0 is VZVirtioSoundDeviceOutputStreamConfiguration }
                )
            }

        directorySharingTags = c.directorySharingDevices.compactMap { ($0 as? VZVirtioFileSystemDeviceConfiguration)?.tag }
        socketDeviceCount = c.socketDevices.count
        if #available(macOS 15.0, *) {
            usbControllerClasses = c.usbControllers.map { className($0) }
        } else {
            usbControllerClasses = []
        }
        entropyDeviceCount = c.entropyDevices.count
        consoleDeviceClasses = c.consoleDevices.map { className($0) }
        keyboardClasses = c.keyboards.map { className($0) }
        pointingDeviceClasses = c.pointingDevices.map { className($0) }
    }

    /// Describes the first difference between this description and another one, or `nil` if they're equivalent.
    func firstDifference(from other: SavedSessionRuntimeDescription) -> String? {
        if cpuCount != other.cpuCount { return "The number of CPU cores is different." }
        if memorySize != other.memorySize { return "The amount of memory is different." }
        if platformClass != other.platformClass || bootLoaderClass != other.bootLoaderClass { return "The platform is different." }
        if storage != other.storage { return "The storage devices are different." }
        if network != other.network { return "The network devices are different." }
        if graphicsClasses != other.graphicsClasses || displays != other.displays { return "The displays are different." }
        if audio != other.audio { return "The audio devices are different." }
        if directorySharingTags != other.directorySharingTags { return "The shared folder devices are different." }
        if socketDeviceCount != other.socketDeviceCount { return "The guest communication device is different." }
        if usbControllerClasses != other.usbControllerClasses { return "The USB controllers are different." }
        if entropyDeviceCount != other.entropyDeviceCount { return "The entropy devices are different." }
        if consoleDeviceClasses != other.consoleDeviceClasses { return "The console devices are different." }
        if keyboardClasses != other.keyboardClasses || pointingDeviceClasses != other.pointingDeviceClasses { return "The input devices are different." }
        return nil
    }
}
