//
//  VirtualUIConstants.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import Foundation
import OSLog
@_exported import VirtualCore

struct VirtualUIConstants {
    static let subsystemName = "codes.rambo.VirtualUI"
}

private final class _VirtualUIStub { }

public extension Bundle {
    static let virtualUI = Bundle(for: _VirtualUIStub.self)
}
