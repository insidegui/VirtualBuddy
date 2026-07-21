import Foundation
import os
import Combine

final class DeviceRestoreDriver: @unchecked Sendable {
    private let logger: Logger
    private let ecid: ECID
    private let bundleURL: URL
    private let variantName: String
    private let backend: any DeviceRestoreBackend

    private let personalizedBundleURL: URL
    private let logDirectoryURL: URL

    let artifactStorageURL: URL
    let loggers: DeviceRestoreLoggers

    init(ecid: ECID, bundleURL: URL, variantName: String = "Customer Erase Install (IPSW)", backend: any DeviceRestoreBackend) throws {
        self.logger = Logger(subsystem: kVirtualInstallationSubsystem, category: "\(String(describing: Self.self))(\(ecid))")
        self.ecid = ecid
        self.bundleURL = bundleURL
        self.variantName = variantName
        self.backend = backend

        self.artifactStorageURL = URL.viApplicationSupportURL
        self.personalizedBundleURL = try artifactStorageURL
            .appending(path: "Personalized_\(bundleURL.deletingPathExtension().lastPathComponent)_\(ecid)_\(Int(Date.now.timeIntervalSinceReferenceDate))", directoryHint: .isDirectory)
            .ensureExistingDirectory(createIfNeeded: true)

        let logRootURL = try artifactStorageURL
            .appending(path: "Logs", directoryHint: .isDirectory)
            .ensureExistingDirectory(createIfNeeded: true)

        let logBaseURL = try logRootURL
            .appending(path: "Restore_\(ecid)_\(UUID().uuidString)", directoryHint: .isDirectory)
            .ensureExistingDirectory(createIfNeeded: true)

        self.logDirectoryURL = logBaseURL

        let loggers = DeviceRestoreLoggers(
            global: RestoreLog(fileURL: logBaseURL.appending(path: "global.log")),
            device: RestoreLog(fileURL: logBaseURL.appending(path: "device.log")),
            host: RestoreLog(fileURL: logBaseURL.appending(path: "host.log")),
            serial: RestoreLog(fileURL: logBaseURL.appending(path: "serial.log"))
        )

        self.loggers = loggers
    }

    func start(overrideOptions: RestoreOptionsDictionary? = nil, progressHandler: @escaping @Sendable (_ state: DeviceRestoreState) -> ()) throws {
        let options: RestoreOptionsDictionary
        if let overrideOptions {
            options = overrideOptions
        } else {
            options = buildRestoreOptions()
        }

        logger.debug("Start with options \(String(describing: options))")

        try backend.restore(deviceECID: ecid, options: options, loggers: loggers) { [weak self] info in
            do {
                var state = try DeviceRestoreState(info: info)

                if case .failure(let reportedError) = state.outcome {
                    let error = reportedError ?? self?.loggers.mostRecentRestoreError.map(CodableError.init)
                    state = state.replacingFailure(error: error, logFileURLs: self?.loggers.fileURLs ?? [])
                }

                progressHandler(state)

                if case .success = state.outcome {
                    self?.discardLogs()
                }
            } catch {
                self?.logger.error("Failed to parse progress info: \(error, privacy: .public). Info:\n\(info, privacy: .public)")
            }
        }
    }

    private func discardLogs() {
        guard FileManager.default.fileExists(atPath: logDirectoryURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: logDirectoryURL)
        } catch {
            logger.error("Failed to discard logs for a successful restore: \(error, privacy: .public)")
        }
    }

    private static let preservePersonalizedBundles = ProcessInfo.processInfo.environment["VI_PRESERVE_PERSONALIZED_BUNDLES"] == "1"

    private func buildRestoreOptions() -> RestoreOptionsDictionary {
        [
            "AuthInstallDemotionPolicyOverride": "Don't Demote",
            "AuthInstallEnableSso": 0,
            "AuthInstallPreservePersonalizedBundles": Self.preservePersonalizedBundles ? 1 : 0,
            "AuthInstallSigningServerURL": "https://gs.apple.com:443",
            "AuthInstallVariant": variantName,
            "AutoBootDelay": 0,
            "BootImageType": "User",
            "CreateFilesystemPartitions": true,
            "DFUFileType": "RELEASE",
            "EncryptDataPartition": true,
            "FlashNOR": true,
            "InstallDiags": true,
            "InstallRecoveryOS": true,
            "KernelCacheType": "Release",
            "NORImageType": "production",
            "PersonalizedRestoreBundlePath": personalizedBundleURL.safePath,
            "PostRestoreAction": "Shutdown",
            "ReadOnlyRootFilesystem": true,
            "RecoveryOSFailureIsFatal": true,
            "RecoveryOSOnly": false,
            "RecoveryOSUnpack": false,
            "RelaxedImageVerification": false,
            "RestoreBootArgs": "debug=0x14e serial=3 rd=md0 nand-enable-reformat=1 -progress -restore",
            "RestoreBundlePath": bundleURL.safePath,
            "SystemImageType": "User",
            "UpdateBaseband": true,
            "WaitForDeviceConnectionToFinishStateMachine": false,
        ]
    }
}
