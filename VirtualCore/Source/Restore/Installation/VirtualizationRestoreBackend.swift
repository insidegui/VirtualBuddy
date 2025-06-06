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

    private let virtualMachineSubject = PassthroughSubject<VZVirtualMachine?, Never>()
    public var virtualMachine: AnyPublisher<VZVirtualMachine?, Never> { virtualMachineSubject.eraseToAnyPublisher() }

    public func install() async throws {
        let installModel = model.forInstallation()

        let config = try await VMInstance.makeConfiguration(for: installModel, installImageURL: restoreImageFileURL)

        let vm = VZVirtualMachine(configuration: config)

        await MainActor.run {
            virtualMachineSubject.send(vm)
        }

        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreImageFileURL)

        _installer = installer

        createInternalProgressObservations(with: installer)

        defer {
            UILog("Cleaning up installation")

            cancellables.removeAll()
            _installer = nil
            virtualMachineSubject.send(nil)
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

extension VBVirtualMachine {
    /// Returns a copy of the model configured for use during installation.
    func forInstallation() -> Self {
        var mself = self

        /// Use a fixed 1080p display resolution for installation.
        mself.configuration.hardware.displayDevices = [.fullHD]

        return mself
    }
}
