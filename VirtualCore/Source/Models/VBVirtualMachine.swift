import Foundation
import UniformTypeIdentifiers

public struct VBVirtualMachine: Identifiable, Hashable {
    public var id: String { bundleURL.absoluteString }
    public let bundleURL: URL
    public var name: String { bundleURL.deletingPathExtension().lastPathComponent }
    public internal(set) var NVRAM = [VBNVRAMVariable]()
}

public extension VBVirtualMachine {
    static let bundleExtension = "vbvm"
}

public extension VBVirtualMachine {
    static let preview = VBVirtualMachine(bundleURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Sample.vbvm"))
}

extension VBVirtualMachine {
    
    var diskImagePath: String {
        bundleURL.appendingPathComponent("Disk.img").path
    }
    
    var extraDiskImagePath: String {
        bundleURL.appendingPathComponent("Disk2.img").path
    }

    var auxiliaryStorageURL: URL {
        bundleURL.appendingPathComponent("AuxiliaryStorage")
    }
    
    var machineIdentifierURL: URL {
        bundleURL.appendingPathComponent("MachineIdentifier")
    }
    
    var hardwareModelURL: URL {
        bundleURL.appendingPathComponent("HardwareModel")
    }

}

public extension UTType {
    static let virtualBuddyVM = UTType(exportedAs: "codes.rambo.VirtualBuddy.VM", conformingTo: .bundle)
}
