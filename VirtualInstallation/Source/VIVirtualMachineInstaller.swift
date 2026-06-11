import Foundation
import Virtualization
import os

public final class VIVirtualMachineInstaller: @unchecked Sendable {
    public let ecid: ECID
    public let bundleURL: URL
    private let client: VirtualInstallationClient
    public let progress: Progress

    public init(ecid: ECID, bundleURL: URL) {
        self.ecid = ecid
        self.bundleURL = bundleURL
        self.client = VirtualInstallationClient()
        self.progress = Progress()
        progress.totalUnitCount = 100
    }

    public func install() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> () in
            Task {
                for await event in client.eventPublisher.values {
                    switch event {
                    case .connectionFailed(let failure):
                        continuation.resume(throwing: failure)
                    case .stateChanged(let state):
                        await updateProgress(with: state)

                        if let outcome = state.outcome {
                            switch outcome {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                continuation.resume(throwing: error ?? CocoaError(.coderValueNotFound))
                            }
                        }
                    }
                }
            }

            client.startVirtualMachineInstallation(ecid: ecid, restoreBundleURL: bundleURL) { error in
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
