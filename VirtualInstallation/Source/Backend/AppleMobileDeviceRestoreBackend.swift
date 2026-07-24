import Foundation
import OSLog

final class AppleMobileDeviceRestoreBackend: DeviceRestoreBackend, @unchecked Sendable {
    private let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: AppleMobileDeviceRestoreBackend.self))

    private var progressHandler: DeviceRestoreProgressClosure? = nil

    func restore(deviceECID: ECID, options: [String : AnyHashable], loggers: DeviceRestoreLoggers, progress: @escaping DeviceRestoreProgressClosure) throws {
        guard let device = VIWaitForDeviceWithECID(deviceECID, .unknown, 5000) else {
            logger.fault("Couldn't find device with ECID \(deviceECID)")
            throw NSError.viDeviceNotFound
        }

        let deviceState = AMRestorableDeviceGetState(device)
        logger.notice("Found device \(deviceECID) with state \(deviceState, privacy: .public)")

        self.progressHandler = progress

        if let global = loggers.global {
            if !AMRestorableSetGlobalLogFileURL(global.fileURL as CFURL) {
                logger.warning("Failed to set global log file URL")
            }
        }
        if let serial = loggers.serial {
            if !AMRestorableDeviceSetLogFileURL(device, serial.fileURL as CFURL, "SerialLogType" as CFString) {
                logger.warning("Failed to set serial log file URL")
            }
        }
        if let host = loggers.host {
            if !AMRestorableDeviceSetLogFileURL(device, host.fileURL as CFURL, "HostLogType" as CFString) {
                logger.warning("Failed to set host log file URL")
            }
        }
        if let deviceLog = loggers.device {
            if !AMRestorableDeviceSetLogFileURL(device, deviceLog.fileURL as CFURL, "DeviceLogType" as CFString) {
                logger.warning("Failed to set device log file URL")
            }
        }

        let refCon = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

        AMRestorableDeviceRestore(device, options as CFDictionary, { device, info, refCon in
            guard let refCon else { return }

            let backend = unsafeBitCast(refCon, to: AppleMobileDeviceRestoreBackend.self)

            #if DEBUG
            backend.logger.trace("PROGRESS: \(info)")
            #endif

            backend.progressHandler?(info)
        }, refCon)
    }
}
