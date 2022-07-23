//
//  VMConfigurationViewModel.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

public enum VMConfigurationContext: Int {
    case preInstall
    case postInstall
}

public final class VMConfigurationViewModel: ObservableObject {
    
    @Published var config: VBMacConfiguration {
        didSet {
            /// Reset display preset when changing display settings.
            /// This is so the warning goes away, if any warning is being shown.
            if config.hardware.displayDevices != oldValue.hardware.displayDevices,
               config.hardware.displayDevices.first != selectedDisplayPreset?.device
            {
                selectedDisplayPreset = nil
            }
        }
    }
    
    @Published public internal(set) var supportState: VBMacConfiguration.SupportState = .supported
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    @Published private(set) var vm: VBVirtualMachine

    public let context: VMConfigurationContext
    
    public init(_ vm: VBVirtualMachine, context: VMConfigurationContext = .postInstall) {
        self.config = vm.configuration
        self.vm = vm
        self.context = context
        
        Task { await validate() }
    }

    @discardableResult
    public func validate() async -> VBMacConfiguration.SupportState {
        let updatedState = await config.validate(for: vm, skipVirtualizationConfig: context == .preInstall)

        await MainActor.run {
            supportState = updatedState
        }

        return updatedState
    }
    
    public func createImage(for device: VBStorageDevice) async throws {
        guard let image = device.managedImage else {
            throw Failure("Only managed disk images can be created.")
        }
        
        let settings = DiskImageGenerator.ImageSettings(for: image, in: vm)
        
        try await DiskImageGenerator.generateImage(with: settings)
    }

    public func updateBootStorageDevice(with image: VBManagedDiskImage) {
        guard let idx = config.hardware.storageDevices.firstIndex(where: { $0.isBootVolume }) else {
            fatalError("Missing boot device in VM configuration")
        }

        var device = config.hardware.storageDevices[idx]
        device.backing = .managedImage(image)
        config.hardware.addOrUpdate(device)
    }
    
}
