import Foundation

struct DeviceRestoreLoggers: @unchecked Sendable {
    var global: RestoreLog? = nil
    var device: RestoreLog? = nil
    var host: RestoreLog? = nil
    var serial: RestoreLog? = nil

    var fileURLs: [URL] {
        [global, device, host, serial].compactMap { log in
            guard let fileURL = log?.fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return fileURL
        }
    }

    var mostRecentRestoreError: NSError? {
        [global, host, device, serial]
            .lazy
            .compactMap { $0?.mostRecentRestoreError() }
            .first
    }
}

typealias DeviceRestoreProgressClosure = @Sendable (_ info: CFDictionary) -> Void

protocol DeviceRestoreBackend: AnyObject {
    func restore(deviceECID: ECID,
                 options: [String: AnyHashable],
                 loggers: DeviceRestoreLoggers,
                 progress: @escaping DeviceRestoreProgressClosure) throws
}
