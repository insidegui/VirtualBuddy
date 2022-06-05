//
//  VirtualCoreConstants.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 02/06/22.
//

import Foundation
import OSLog

struct VirtualCoreConstants {
    static let subsystemName = "codes.rambo.VirtualCore"
}

private final class _VirtualCoreStub { }

public extension Bundle {
    static let virtualCore = Bundle(for: _VirtualCoreStub.self)
}
