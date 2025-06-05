import Foundation
import Virtualization
import BuddyKit
import OSLog
import Combine

public final class VirtualizationRestoreBackend: RestoreBackend {
    public let model: VBVirtualMachine
    public let restoreImageFileURL: URL

    public init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL) {
        self.model = model
        self.restoreImageFileURL = restoreImageFileURL
    }

    private var cancellables = Set<AnyCancellable>()

    public let progress = Progress()

    private var _installer: VZMacOSInstaller?

    public func install() async throws {
        let config = try await VMInstance.makeConfiguration(for: model, installImageURL: restoreImageFileURL)

        let vm = VZVirtualMachine(configuration: config)

        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreImageFileURL)

        _installer = installer

        createInternalProgressObservations(with: installer)

        defer {
            UILog("Cleaning up installation")

            cancellables.removeAll()
            _installer = nil
        }

        try await installer.install()
    }

    private func createInternalProgressObservations(with installer: VZMacOSInstaller) {
        installer.progress
            .publisher(for: \.totalUnitCount, options: [.initial, .new])
            .sink { [weak self] value in
                self?.progress.totalUnitCount = value
            }
            .store(in: &cancellables)

        installer.progress
            .publisher(for: \.completedUnitCount, options: [.initial, .new])
            .sink { [weak self] value in
                self?.progress.completedUnitCount = value
            }
            .store(in: &cancellables)
    }
}
