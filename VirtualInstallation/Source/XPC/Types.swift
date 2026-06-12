import Foundation
import OSLog

public typealias ECID = UInt64

public typealias RestoreOptionsDictionary = [String : AnyHashable]

public typealias RestoreOperation = Int32

/// A type that can be used to wrap any `Error` as a `Codable` and `Hashable` container that can be stored as part of another type.
public nonisolated struct CodableError: LocalizedError, CustomNSError, Codable, Hashable, Sendable {
    public private(set) var domain: String
    public private(set) var code: Int
    public private(set) var errorDescription: String
    public private(set) var failureReason: String?
    public private(set) var helpAnchor: String?
    public private(set) var recoverySuggestion: String?
    public private(set) var info: [String: String]
}

public nonisolated extension CodableError {
    init(_ error: any Error) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.errorDescription = nsError.localizedDescription
        self.failureReason = nsError.localizedFailureReason
        self.helpAnchor = nsError.helpAnchor
        self.recoverySuggestion = nsError.localizedRecoverySuggestion
        self.info = [:]

        for (key, value) in nsError.userInfo {
            self.info[key] = String(describing: value)
        }
    }

    init(message: String) {
        self.domain = kVirtualInstallationSubsystem
        self.code = 0
        self.errorDescription = message
        self.info = [NSLocalizedFailureReasonErrorKey : message]
    }
}


public enum DeviceRestoreOutcome: Hashable, Codable, Sendable {
    case success
    case failure(_ error: CodableError?)

    public var isFailure: Bool {
        if case .failure = self {
            true
        } else {
            false
        }
    }
}

public struct DeviceRestoreState: Hashable, Codable, Sendable {
    public let progress: Double
    public let overallProgress: Double?
    public let operation: RestoreOperation
    public let operationName: String?
    public let status: String?
    public private(set) var outcome: DeviceRestoreOutcome?
}

// MARK: - AMD Serialization

private extension DeviceRestoreOutcome {
    init?(info: [String: Any], status: String) {
        if status.caseInsensitiveCompare("Successful") == .orderedSame {
            self = .success
        } else if status.caseInsensitiveCompare("Failed") == .orderedSame {
            self = .failure((info["Error"] as? NSError).flatMap(CodableError.init))
        } else {
            return nil
        }
    }
}

extension DeviceRestoreState {
    static let logger = Logger(subsystem: kVirtualInstallationSubsystem, category: String(describing: DeviceRestoreState.self))

    init(info: CFDictionary) throws(CodableError) {
        guard let dict = info as? [String: Any] else {
            throw CodableError(message: "Info dictionary in progress report doesn't match expected dictionary type")
        }

        let intProgress = dict["Progress"] as? Int ?? 0
        let intOverallProgress = dict["OverallProgress"] as? Int ?? 0
        self.status = dict["Status"] as? String
        self.progress = Double(intProgress) / 100.0
        self.overallProgress = intOverallProgress <= 0 ? nil : Double(intOverallProgress) / 100.0
        self.operation = dict["Operation"] as? RestoreOperation ?? 0

        let operationNameFormat = AMRLocalizedCopyStringForAMROperation(operation) as String

        /// When there's a `QueuePosition`, the string is a format string.
        if let queuePosition = dict["QueuePosition"] as? Int, operationNameFormat.contains("%d") {
            self.operationName = String(format: operationNameFormat, queuePosition)
        } else {
            self.operationName = operationNameFormat
        }

        if let status, status != "Restoring" {
            self.outcome = DeviceRestoreOutcome(info: dict, status: status)
        } else {
            self.outcome = nil
        }
    }

    func replacingOutcome(with error: NSError) -> Self {
        var mSelf = self
        mSelf.outcome = .failure(CodableError(error))
        return mSelf
    }
}
