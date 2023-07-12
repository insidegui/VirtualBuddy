//
//  VirtualUIConstants.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import Foundation
import OSLog
@_exported import VirtualCore
@_exported import VirtualUIFoundation

struct VirtualUIConstants {
    static let subsystemName = "codes.rambo.VirtualUI"
}

@available(swift, obsoleted: 1.0, message: "Provided for Objective-C compatibility, don't use in Swift code.")
@objcMembers
public final class _VirtualUIConstantsObjC: NSObject {
    public class var subsystemName: String { VirtualUIConstants.subsystemName }
}

private final class _VirtualUIStub { }

public extension Bundle {
    static let virtualUI = Bundle(for: _VirtualUIStub.self)
}
