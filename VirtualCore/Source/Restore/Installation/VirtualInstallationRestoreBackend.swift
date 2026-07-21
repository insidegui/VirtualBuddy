import Foundation
import Virtualization
import OSLog
import Combine
import VirtualInstallation

public final class VirtualInstallationRestoreBackend: VirtualMachineProvidingRestoreBackend {
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VirtualInstallationRestoreBackend.self))

    #if DEBUG
    /// Enables an end-to-end VirtualInstallation failure using `-VBSimulateInstallFailure YES`.
    public static var isFailureSimulationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "VBSimulateInstallFailure")
    }

    private static let failureSimulationECID: ECID = 0xF411_0000_0000_0001
    #endif

    public var consolePredicate: LogStreamer.Predicate { .custom(kVirtualInstallationUnifiedLogPredicate) }

    public let model: VBVirtualMachine
    public let restoreImageFileURL: URL

    public init(model: VBVirtualMachine, restoringFromImageAt restoreImageFileURL: URL) {
        self.model = model
        self.restoreImageFileURL = restoreImageFileURL
    }

    private var cancellables = Set<AnyCancellable>()

    public let progress = Progress()

    private var _installer: VIVirtualMachineInstaller?
    private var _virtualMachine: VZVirtualMachine?

    private let virtualMachineSubject = PassthroughSubject<VZVirtualMachine?, Never>()
    public var virtualMachine: AnyPublisher<VZVirtualMachine?, Never> { virtualMachineSubject.eraseToAnyPublisher() }

    public func install() async throws {
        #if DEBUG
        if Self.isFailureSimulationEnabled {
            logger.notice("Running debug-only end-to-end install failure simulation")
            try await runInstaller(ecid: Self.failureSimulationECID, simulateFailure: true)
            return
        }
        #endif

        logger.debug("Install - creating configuration")

        let installModel = model.forInstallation()

        let config = try await VMInstance.makeConfiguration(for: installModel, installImageURL: restoreImageFileURL)

        let vm = VZVirtualMachine(configuration: config)
        _virtualMachine = vm

        await MainActor.run {
            virtualMachineSubject.send(vm)
        }

        let options = VZMacOSVirtualMachineStartOptions()
        options._forceDFU = true

        logger.debug("Requesting vm start")

        try await vm.start(options: options)

        let ecid = try installModel.ECID.require("Failed to obtain virtual machine ECID for installation.")

        logger.debug("Activating installer")

        try await runInstaller(ecid: ecid, simulateFailure: false)
    }

    private func runInstaller(ecid: ECID, simulateFailure: Bool) async throws {
        let installer = VIVirtualMachineInstaller(
            ecid: ecid,
            bundleURL: restoreImageFileURL,
            simulateFailure: simulateFailure
        )

        _installer = installer

        createInternalProgressObservations(with: installer)

        defer {
            cleanup()
        }

        try Task.checkCancellation()

        do {
            try await installer.install()
        } catch let error as DeviceRestoreFailure {
            throw RestoreFailure(
                message: error.localizedDescription,
                diagnosticFileURLs: error.logFileURLs
            )
        }
    }

    public func cancel() async {
        logger.warning("Installation cancelled by client.")

        progress.cancel()

        if let _virtualMachine, _virtualMachine.canStop {
            do {
                logger.info("Stopping installation VM...")

                try await _virtualMachine.stop()

                logger.info("Installation VM stopped.")
            } catch {
                logger.error("Error forcing installation VM stop - \(error, privacy: .public)")
            }
        }

        cleanup()
    }

    private func cleanup() {
        logger.debug("Cleaning up installation.")

        cancellables.removeAll()
        _installer = nil
        _virtualMachine = nil
        virtualMachineSubject.send(nil)
    }

    private func createInternalProgressObservations(with installer: VIVirtualMachineInstaller) {
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
