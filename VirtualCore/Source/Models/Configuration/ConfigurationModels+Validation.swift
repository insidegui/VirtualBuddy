//
//  ConfigurationModels+Validation.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Cocoa

public extension VBMacConfiguration {
    
    func validate(for model: VBVirtualMachine, skipVirtualizationConfig: Bool) async -> SupportState {
        var tempModel = model
        tempModel.configuration = self

        guard !skipVirtualizationConfig else {
            return hostSupportState
        }

        do {
            let config = try await VMInstance.makeConfiguration(for: tempModel)
            
            try config.validate()
            
            return hostSupportState
        } catch {
            return hostSupportState.merged(with: .unsupported([error.localizedDescription]))
        }
    }
    
}

public extension VBMacConfiguration {
    /// The state of this configuration for the current host, used to indicate
    /// possible issues the user may have with it, or to prevent unsupported
    /// configurations from being saved.
    var hostSupportState: SupportState {
        var warnings = [String]()
        var errors = [String]()
        
        if !hardware.pointingDevice.kind.isSupportedByHost {
            errors.append("\(hardware.pointingDevice.kind.name) requires macOS 13 or later.")
        }
        if sharedClipboardEnabled, !VBMacConfiguration.isNativeClipboardSharingSupported {
            warnings.append(VBMacConfiguration.clipboardSharingNotice)
        }
        if hasSharedFolders {
            if VBMacConfiguration.isFileSharingSupported {
                warnings.append(VBMacConfiguration.fileSharingNotice)
            } else {
                errors.append(VBMacConfiguration.fileSharingNotice)
            }
        }
        if hardware.networkDevices.contains(where: { $0.kind == .bridge }), !VBNetworkDevice.appSupportsBridgedNetworking {
            errors.append(VBNetworkDevice.bridgeUnsupportedMessage)
        }
        
        return SupportState(errors: errors, warnings: warnings)
    }
    
    static let isNativeClipboardSharingSupported: Bool = {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }()

    static let isFileSharingSupported: Bool = {
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

    static let fileSharingNotice: String = {
        let tip = "For previous OS versions, you can use the standard macOS file sharing feature in System Preferences > Sharing."

        if isFileSharingSupported {
            return "File sharing requires the virtual machine to be running macOS 13 or later. \(tip)"
        } else {
            return "File sharing requires both the host Mac and the virtual machine to be running macOS 13 or later. \(tip)"
        }
    }()
}

public extension VBMacConfiguration.SupportState {
    var errors: [String] {
        guard case .unsupported(let errors) = self else {
            return []
        }
        return errors
    }
    
    var warnings: [String] {
        guard case .warnings(let warnings) = self else {
            return []
        }
        return warnings
    }
    
    var allowsSaving: Bool { errors.isEmpty }
    
    init(errors: [String] = [], warnings: [String] = []) {
        if errors.isEmpty {
            if warnings.isEmpty {
                self = .supported
            } else {
                self = .warnings(warnings)
            }
        } else {
            self = .unsupported(errors)
        }
    }
    
    func merged(with other: Self) -> Self {
        Self.init(errors: errors + other.errors, warnings: warnings + other.warnings)
    }
}

public extension VBNetworkDevice {
    static var appSupportsBridgedNetworking: Bool {
        NSApplication.shared.hasEntitlement("com.apple.vm.networking")
    }
    
    static let bridgeUnsupportedMessage = "Bridged network devices are not available in this build of the app."
}

public extension VBPointingDevice.Kind {
    var warning: String? {
        guard self == .trackpad else { return nil }
        return "Trackpad is only recognized by VMs running macOS 13 and later."
    }
    
    var error: String? {
        guard !isSupportedByHost else { return nil }
        return "Trackpad requires both host and VM to be on macOS 13 or later."
    }

    var isSupportedByHost: Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return self == .mouse
        }
    }
}
