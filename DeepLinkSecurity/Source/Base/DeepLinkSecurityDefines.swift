import Foundation
import OSLog

struct DeepLinkSecurityDefines {
    static let subsystem = "codes.rambo.DeepLinkSecurity"
}

struct DeepLinkError: LocalizedError {
    var errorDescription: String?
    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}

extension Logger {
    static func deepLinkLogger<T>(for type: T.Type) -> Logger {
        Logger(subsystem: DeepLinkSecurityDefines.subsystem, category: String(describing: type))
    }
}
