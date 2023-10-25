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

