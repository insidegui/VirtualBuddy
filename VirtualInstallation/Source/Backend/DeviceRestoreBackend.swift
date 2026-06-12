import Foundation

struct DeviceRestoreLoggers: @unchecked Sendable {
    var global: RestoreLog? = nil
    var device: RestoreLog? = nil
    var host: RestoreLog? = nil
    var serial: RestoreLog? = nil
}

typealias DeviceRestoreProgressClosure = @Sendable (_ info: CFDictionary) -> Void

protocol DeviceRestoreBackend: AnyObject {
    func restore(deviceECID: ECID,
                 options: [String: AnyHashable],
                 loggers: DeviceRestoreLoggers,
                 progress: @escaping DeviceRestoreProgressClosure) throws
}
