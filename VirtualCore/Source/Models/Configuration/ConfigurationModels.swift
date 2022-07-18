//
//  ConfigurationModels.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 17/07/22.
//

import Foundation
import SystemConfiguration

public struct VBDisplayDevice: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name = "Default"
    public var width = 1920
    public var height = 1080
    public var pixelsPerInch = 144
}

public struct VBNetworkDevice: Identifiable, Hashable, Codable {
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        case NAT
        case bridge
    }

    public var id = "Default"
    public var name = "Default"
    public var kind = Kind.NAT
    public var macAddress = VZMACAddress.randomLocallyAdministered().string
}

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

public struct VBSoundDevice: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name = "Default"
    public var enableOutput = true
    public var enableInput = true
}

public struct VBMacDevice: Hashable, Codable {
    public var cpuCount: Int
    public var memorySize: UInt64
    public var pointingDevice: VBPointingDevice
    public var displayDevices: [VBDisplayDevice]
    public var networkDevices: [VBNetworkDevice]
    public var soundDevices: [VBSoundDevice]
    public var NVRAM = [VBNVRAMVariable]()
}

public struct VBSharedFolder: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name: String { url.lastPathComponent }
    public var url: URL
    public var isReadOnly = true
}

public struct VBMacConfiguration: Hashable, Codable {

    public var hardware = VBMacDevice.default
    public var sharedFolders = [VBSharedFolder]()

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

// MARK: - Helpers

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

    static var maximumDisplayWidth: Int { Self.matchHost.width }

    static var maximumDisplayHeight: Int { Self.matchHost.height }

    static let displayWidthRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayWidth
    }()

    static let displayHeightRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayHeight
    }()

    static let minimumDisplayPPI = 144

    static let maximumDisplayPPI: Int = {
        Self.default.pixelsPerInch
    }()

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

extension ProcessInfo {
    var vb_hostName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as? String ?? "This Mac"
    }
}
