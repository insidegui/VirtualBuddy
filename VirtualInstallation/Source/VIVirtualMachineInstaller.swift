import Foundation
import Virtualization
import os

public final class VIVirtualMachineInstaller: @unchecked Sendable {
    public let ecid: ECID
    public let bundleURL: URL
    private let simulateFailure: Bool
    private let client: VirtualInstallationClient
    public let progress: Progress
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: VIVirtualMachineInstaller.self))

    /// - Parameter simulateFailure: In debug builds, requests an end-to-end simulated failure from the XPC service.
    /// Ignored in release builds.
    public init(ecid: ECID, bundleURL: URL, simulateFailure: Bool = false) {
        self.ecid = ecid
        self.bundleURL = bundleURL
        #if DEBUG
        self.simulateFailure = simulateFailure
        #else
        self.simulateFailure = false
        #endif
        self.client = VirtualInstallationClient()
        self.progress = Progress()
        progress.totalUnitCount = 100
    }

    public func install() async throws {
        defer { logger.debug("\(#function, privacy: .public) is returning now") }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> () in
            Task {
                for await event in client.eventPublisher.values {
                    switch event {
                    case .connectionFailed(let failure):
                        continuation.resume(throwing: failure)
                    case .stateChanged(let state):
                        await updateProgress(with: state)

                        if let outcome = state.outcome {
                            logger.info("Received state update with outcome: \(String(describing: outcome), privacy: .public)")

                            switch outcome {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                continuation.resume(throwing: DeviceRestoreFailure(
                                    underlyingError: error,
                                    logFileURLs: state.logFileURLs
                                ))
                            }
                        }
                    }
                }
            }

            client.startVirtualMachineInstallation(
                ecid: ecid,
                restoreBundleURL: bundleURL,
                simulateFailure: simulateFailure
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor private func updateProgress(with state: DeviceRestoreState) {
        if let status = state.status {
            progress.localizedDescription = status
        }
        if let operationName = state.operationName {
            progress.localizedAdditionalDescription = operationName
        }
        if let overallProgressPercent = state.overallProgress {
            progress.completedUnitCount = Int64(overallProgressPercent * 100)
        }
    }
}
