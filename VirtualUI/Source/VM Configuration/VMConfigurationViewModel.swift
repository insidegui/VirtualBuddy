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

struct PendingDiskImageResizeConfirmation: Identifiable, Hashable {
    var image: VBManagedDiskImage
    var originalSize: UInt64
    var proposedSize: UInt64
    var deviceName: String

    var id: String { image.id }
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

    @Published private(set) var pendingDiskImageResizeIDs = Set<String>()

    @Published private(set) var pendingDiskImageResizeConfirmations = [String: PendingDiskImageResizeConfirmation]()

    public let context: VMConfigurationContext
    
    public init(_ vm: VBVirtualMachine, context: VMConfigurationContext = .postInstall, resolvedRestoreImage: ResolvedRestoreImage? = nil) {
        self.config = vm.configuration
        self.vm = vm
        self.context = context
        self.resolvedRestoreImage = resolvedRestoreImage
        
        applyResolvedFeatureDefaultsIfNeeded()

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

    func markDiskImageResizePending(for image: VBManagedDiskImage) {
        pendingDiskImageResizeIDs.insert(image.id)
    }

    func clearPendingDiskImageResize(for image: VBManagedDiskImage) {
        pendingDiskImageResizeIDs.remove(image.id)
        pendingDiskImageResizeConfirmations.removeValue(forKey: image.id)
    }

    func updateDiskImageResizeConfirmation(
        for image: VBManagedDiskImage,
        originalSize: UInt64,
        deviceName: String,
        isExistingDiskImage: Bool,
        canResize: Bool
    ) {
        guard VBManagedDiskImage.requiresResizeConfirmation(
            isExistingDiskImage: isExistingDiskImage,
            canResize: canResize,
            originalSize: originalSize,
            proposedSize: image.size
        ) else {
            clearPendingDiskImageResize(for: image)
            return
        }

        pendingDiskImageResizeConfirmations[image.id] = PendingDiskImageResizeConfirmation(
            image: image,
            originalSize: originalSize,
            proposedSize: image.size,
            deviceName: deviceName
        )
    }

    var hasPendingDiskImageResizeConfirmations: Bool {
        !pendingDiskImageResizeConfirmations.isEmpty
    }

    func hasPendingDiskImageResizeConfirmation(for image: VBManagedDiskImage?) -> Bool {
        guard let image else { return false }
        return pendingDiskImageResizeConfirmations[image.id] != nil
    }

    func diskImageResizeConfirmationMessage(for image: VBManagedDiskImage? = nil, formatter: ByteCountFormatter) -> String {
        let confirmations = sortedPendingDiskImageResizeConfirmations(for: image)

        if confirmations.count == 1, let confirmation = confirmations.first {
            let originalSize = formatter.string(fromByteCount: Int64(confirmation.originalSize))
            let proposedSize = formatter.string(fromByteCount: Int64(confirmation.proposedSize))

            return "This will resize the disk image from \(originalSize) to \(proposedSize). The resize will run automatically the next time the virtual machine starts and may take some time. This operation cannot be undone."
        }

        guard !confirmations.isEmpty else { return "" }

        return "This will resize \(confirmations.count) disk images. The resize will run automatically the next time the virtual machine starts and may take some time. This operation cannot be undone."
    }

    func firstFileVaultProtectedPendingResizeName(for image: VBManagedDiskImage? = nil) async -> String? {
        for confirmation in sortedPendingDiskImageResizeConfirmations(for: image) {
            if await vm.checkFileVaultForDiskImage(confirmation.image) {
                return confirmation.deviceName
            }
        }

        return nil
    }

    func confirmPendingDiskImageResizes(for image: VBManagedDiskImage? = nil) {
        for confirmation in sortedPendingDiskImageResizeConfirmations(for: image) {
            markDiskImageResizePending(for: confirmation.image)
            pendingDiskImageResizeConfirmations.removeValue(forKey: confirmation.image.id)
        }
    }

    private func sortedPendingDiskImageResizeConfirmations(for image: VBManagedDiskImage? = nil) -> [PendingDiskImageResizeConfirmation] {
        if let image {
            guard let confirmation = pendingDiskImageResizeConfirmations[image.id] else { return [] }
            return [confirmation]
        }

        return pendingDiskImageResizeConfirmations.values.sorted { $0.deviceName < $1.deviceName }
    }

    func applyPendingDiskImageResizeIDs(to metadata: inout VBVirtualMachine.Metadata) {
        for imageID in pendingDiskImageResizeIDs {
            metadata.pendingDiskImageResizeIDs.insert(imageID)
        }
    }
    
}

// MARK: - Feature Defaults

private extension VMConfigurationViewModel {
    func applyResolvedFeatureDefaultsIfNeeded() {
        guard context == .preInstall else { return }
        guard let resolvedRestoreImage else { return }

        var updated = config

        if resolvedRestoreImage.feature(id: CatalogFeatureID.guestApp)?.status.isUnsupported == true {
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
