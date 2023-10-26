//
//  VirtualWormholeConstants.swift
//  VirtualWormholeConstants
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import OSLog

struct VirtualWormholeConstants {
    static let subsystemName = "codes.rambo.VirtualWormhole"

    static let verboseLoggingEnabled: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "WHVerbosePacketLogging")
        #else
        return false
        #endif
    }()

    static let payloadPropagationEnabled: Bool = {
        !UserDefaults.standard.bool(forKey: "WHDisablePayloadPropagation")
    }()

    static let connectionTimeoutInNanoseconds: UInt64 = 15 * NSEC_PER_SEC

    static let pingIntervalInSeconds: TimeInterval = 5.0
}

public typealias WHServicePort = UInt32

/// Each service has its dedicated port and socket connection between guest and host.
/// Default service ports are declared here so that they're easy to manage, but each service
/// declares its port via the ``WormholeService`` protocol.
public extension WHServicePort {
    static let control: WHServicePort = 9000
    static let clipboard: WHServicePort = 9001
    static let darwinNotifications: WHServicePort = 9002
    static let defaultsImport: WHServicePort = 9003
}

extension Logger {
    init<T>(for type: T.Type) {
        self.init(subsystem: VirtualWormholeConstants.subsystemName, category: String(describing: type))
    }
}

private final class _VirtualWormholeStub { }

public extension Bundle {
    static let virtualWormhole = Bundle(for: _VirtualWormholeStub.self)
}

