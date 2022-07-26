#if DEBUG

import Foundation

public extension ProcessInfo {
    
    @objc static let isSwiftUIPreview: Bool = {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }()
    
}

public extension VBVirtualMachine {
    static let preview: VBVirtualMachine = {
        var machine = try! VBVirtualMachine(bundleURL: Bundle.virtualCore.url(forResource: "Preview", withExtension: "vbvm")!)
        machine.configuration = .preview
        return machine
    }()
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
    
}

#endif
