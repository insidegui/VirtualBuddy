//
//  VMConfigurationViewModel.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import Combine
import VirtualCore

public enum VMConfigurationContext: Int {
    case preInstall
    case postInstall

    /// Whether the configuration should be saved continuously as it's changed by the user.
    var shouldAutoSave: Bool {
        switch self {
        case .preInstall: true
        case .postInstall: false
        }
    }
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

    @Published public internal(set) var resolvedRestoreImage: ResolvedRestoreImage? {
        didSet {
            applyResolvedFeatureDefaultsIfNeeded()
        }
    }
    
    @Published var selectedDisplayPreset: VBDisplayPreset?
    
    @Published private(set) var vm: VBVirtualMachine

    public let context: VMConfigurationContext

    /// A saved session belongs to the hardware the virtual machine had when it was saved,
    /// so none of it can be changed until the session is resumed and the virtual machine is shut down, or the session is discarded.
    @Published public private(set) var isLockedBySavedSession: Bool

    /// Discards the saved session. Set when something else (such as a controller) owns the virtual machine's lifecycle.
    public var discardSavedSessionHandler: (() async throws -> Void)?

    private var cancellables = Set<AnyCancellable>()

    public init(_ vm: VBVirtualMachine, context: VMConfigurationContext = .postInstall, resolvedRestoreImage: ResolvedRestoreImage? = nil) {
        self.config = vm.configuration
        self.vm = vm
        self.context = context
        self.resolvedRestoreImage = resolvedRestoreImage
        self.isLockedBySavedSession = vm.savedSession != nil
        
        applyResolvedFeatureDefaultsIfNeeded()

        Task { await validate() }

        /// Automatically save configuration as it changes when in a pre-install context.
        /// In a post-install context, configuration is only saved when the user confirms it.
        if context.shouldAutoSave {
            $config
                .removeDuplicates()
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink { [weak self] config in
                    do {
                        self?.vm.configuration = config
                        try self?.vm.saveMetadata()
                    } catch {
                        assert(ProcessInfo.isSwiftUIPreview, "Unexpected metadata write failure: \(error)")
                    }
                }
                .store(in: &cancellables)
        }
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

    /// Discards the saved session, unlocking the configuration.
    @MainActor
    public func discardSavedSession() async throws {
        if let discardSavedSessionHandler {
            try await discardSavedSessionHandler()
        } else {
            try await vm.discardSavedSession()
        }

        vm.reloadSavedSession()
        isLockedBySavedSession = vm.savedSession != nil
    }

    var vmName: String { vm.name }

    /// Whether some of the virtual machine's disk images live outside of it.
    var hasExternalDiskImages: Bool {
        !ExternalDiskImageCopier.externalDevices(of: vm).isEmpty
    }

    /// Copies disk images that live outside of the virtual machine into it, so that they can be part of its saved session.
    ///
    /// The copies are made first and the configuration is only updated once all of them succeeded,
    /// so a failure leaves the configuration the way it was.
    @MainActor
    func copyExternalDiskImagesIntoVirtualMachine() async throws {
        let result = try await ExternalDiskImageCopier().copyExternalDiskImages(of: vm)

        var updatedVM = vm
        updatedVM.configuration.hardware.storageDevices = result.devices

        do {
            try updatedVM.saveMetadata()
        } catch {
            result.discardCopies()
            throw error
        }

        vm = updatedVM

        /// Edits that haven't been saved yet are kept, only the disk images that were copied change.
        let converted = Dictionary(uniqueKeysWithValues: result.devices.map { ($0.id, $0) })
        config.hardware.storageDevices = config.hardware.storageDevices.map { converted[$0.id] ?? $0 }
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

// MARK: - Feature Defaults

private extension VMConfigurationViewModel {
    func applyResolvedFeatureDefaultsIfNeeded() {
        guard context == .preInstall else { return }
        guard let resolvedRestoreImage else { return }

        var updated = config

        if resolvedRestoreImage.version < GuestAppSupport.minimumSystemVersion
            || resolvedRestoreImage.feature(id: CatalogFeatureID.guestApp)?.status.isUnsupported == true {
            updated.guestAdditionsEnabled = false
        }

        if resolvedRestoreImage.feature(id: CatalogFeatureID.trackpad)?.status.isUnsupported == true,
           updated.hardware.pointingDevice.kind == .trackpad
        {
            updated.hardware.pointingDevice.kind = .mouse
        }

        if resolvedRestoreImage.feature(id: CatalogFeatureID.macKeyboard)?.status.isUnsupported == true,
           updated.hardware.keyboardDevice.kind == .mac
        {
            updated.hardware.keyboardDevice.kind = .generic
        }

        if resolvedRestoreImage.feature(id: CatalogFeatureID.displayResize)?.status.isUnsupported == true {
            updated.hardware.displayDevices = updated.hardware.displayDevices.map { device in
                var updatedDevice = device
                updatedDevice.automaticallyReconfiguresDisplay = false
                return updatedDevice
            }
        }

        if resolvedRestoreImage.feature(id: CatalogFeatureID.rosettaSharing)?.status.isUnsupported == true {
            updated.rosettaSharingEnabled = false
        }

        if updated != config {
            config = updated
        }
    }
}
