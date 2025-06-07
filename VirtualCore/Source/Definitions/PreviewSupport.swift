#if DEBUG

import Foundation
import Virtualization

let previewLibraryDirName = "PreviewLibrary"

public extension VBVirtualMachine {
    static func previewMachine(named name: String) -> VBVirtualMachine {
        try! VBVirtualMachine(bundleURL: Bundle.virtualCore.url(forResource: name, withExtension: VBVirtualMachine.bundleExtension, subdirectory: previewLibraryDirName)!)
    }
    static let preview = VBVirtualMachine.previewMachine(named: "Preview")
    static let previewLinux = VBVirtualMachine.previewMachine(named: "Preview-Linux")
}

extension Bundle {
    func requiredPreviewDirectoryURL(named name: String) -> URL {
        guard let url = Bundle.virtualCore.resourceURL?.appending(path: name, directoryHint: .isDirectory) else {
            fatalError("Couldn't get resources URL for VirtualCore bundle")
        }
        precondition(FileManager.default.fileExists(atPath: url.path), "Missing \(name) directory in VirtualCore resources")
        return url
    }
}

public extension VBSettingsContainer {
    static let preview: VBSettingsContainer = {
        let libraryURL = Bundle.virtualCore.requiredPreviewDirectoryURL(named: previewLibraryDirName)
        let container = VBSettingsContainer()
        container.settings.libraryURL = libraryURL
        return container
    }()
}

public extension VMLibraryController {
    static let preview: VMLibraryController = {
        VMLibraryController(settingsContainer: .preview)
    }()
}

public extension VMSavedStatesController {
    static var preview: VMSavedStatesController {
        fatalError("VMSavedStatesController.preview needs to be reimplemented with new VMSavedStatesController requirements")
//        VMSavedStatesController(directoryURL: Bundle.virtualCore.requiredPreviewDirectoryURL(named: "\(previewLibraryDirName)/_SavedStates"))
    }
}

@MainActor
public extension VMController {
    static let preview = VMController(with: .preview, library: .preview)
}

public extension VBMacConfiguration {
    
    static let preview: VBMacConfiguration = {
        var c = VBMacConfiguration.default
        
        c.hardware.storageDevices.append(.init(isBootVolume: false, isEnabled: true, isReadOnly: false, isUSBMassStorageDevice: false, backing: .managedImage(VBManagedDiskImage(filename: "New Device", size: VBManagedDiskImage.minimumExtraDiskImageSize))))
        c.hardware.storageDevices.append(.init(isBootVolume: false, isEnabled: true, isReadOnly: false, isUSBMassStorageDevice: false, backing: .managedImage(VBManagedDiskImage(filename: "Fake Managed Disk", size: VBManagedDiskImage.minimumExtraDiskImageSize, format: .raw))))
        c.hardware.storageDevices.append(.init(isBootVolume: false, isEnabled: true, isReadOnly: false, isUSBMassStorageDevice: false, backing: .customImage(Bundle.virtualCore.url(forResource: "Fake Custom Path Disk", withExtension: "dmg", subdirectory: "Preview.vbvm")!)))
        
        c.sharedFolders = [
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99074")!, url: URL(fileURLWithPath: "/Users/insidegui/Desktop"), isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99075")!, url: URL(fileURLWithPath: "/Users/insidegui/Downloads"), isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99076")!, url: URL(fileURLWithPath: "/Volumes/Rambo/Movies"), isEnabled: false, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99077")!, url: URL(fileURLWithPath: "/Some/Invalid/Path"), isEnabled: true, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99078")!, url: URL(fileURLWithPath: "/Users/insidegui/Music"), isEnabled: true, isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99079")!, url: URL(fileURLWithPath: "/Users/insidegui/Developer"), isEnabled: true, isReadOnly: true),
        ]
        
        return c
    }()
    
    static var networkPreviewNAT: VBMacConfiguration {
        var config = VBMacConfiguration.preview
        config.hardware.networkDevices = [VBNetworkDevice(id: "Default", name: "Default", kind: .NAT, macAddress: "0A:82:7F:CE:C0:58")]
        return config
    }
    
    static var networkPreviewBridge: VBMacConfiguration {
        var config = VBMacConfiguration.preview
        config.hardware.networkDevices = [VBNetworkDevice(id: VBNetworkDevice.defaultBridgeInterfaceID ?? "ERROR", name: "Bridge", kind: .bridge, macAddress: "0A:82:7F:CE:C0:58")]
        return config
    }
    
    static var networkPreviewNone: VBMacConfiguration {
        var config = VBMacConfiguration.preview
        config.hardware.networkDevices = []
        return config
    }
    
    var removingSharedFolders: Self {
        var mSelf = self
        mSelf.sharedFolders = []
        return mSelf
    }
    
    var linuxVirtualMachine: Self {
        var mSelf = self
        mSelf.systemType = .linux
        return mSelf
    }
    
}

public extension VZVirtualMachine {
    /// A dummy `VZVirtualMachine` instance for previews where an instance is needed but nothing  is actually done with it.
    static let preview: VZVirtualMachine = {
        let config = VZVirtualMachineConfiguration()
        /// Sneaky little swizzle to get around validation exception.
        /// This is fine® because it's just for previews.
        if let method = class_getInstanceMethod(VZVirtualMachineConfiguration.self, #selector(VZVirtualMachineConfiguration.validate)) {
            let impBlock: @convention(block) () -> Bool = { return true }
            method_setImplementation(method, imp_implementationWithBlock(impBlock))
        }
        return VZVirtualMachine(configuration: config)
    }()
}

public extension SoftwareCatalog {
    static let previewMac = try! VBAPIClient.fetchBuiltInCatalog(for: .mac)
    static let previewLinux = try! VBAPIClient.fetchBuiltInCatalog(for: .linux)
}

public extension ResolvedCatalog {
    static let previewMac = ResolvedCatalog(environment: .current.guest(platform: .mac), catalog: .previewMac)
    static let previewLinux = ResolvedCatalog(environment: .current.guest(platform: .linux), catalog: .previewLinux)
}

public extension ResolvedCatalogGroup {
    static let previewMac = ResolvedCatalog.previewMac.groups[0]
    static let previewLinux = ResolvedCatalog.previewLinux.groups[0]
}

public extension ResolvedRestoreImage {
    static let previewMac = ResolvedCatalog.previewMac.groups[0].restoreImages[0]
    static let previewLinux = ResolvedCatalog.previewLinux.groups[0].restoreImages[0]
}

#else
public extension ProcessInfo {

    @objc static let isSwiftUIPreview: Bool = false

}
#endif
