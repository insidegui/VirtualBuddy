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

