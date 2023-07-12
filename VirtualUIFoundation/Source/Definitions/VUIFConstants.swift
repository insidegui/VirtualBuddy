import Foundation
import OSLog
@_exported import VirtualCore

struct VUIFConstants {
    static let subsystemName = "codes.rambo.VirtualUIFoundation"
}

@available(swift, obsoleted: 1.0, message: "Provided for Objective-C compatibility, don't use in Swift code.")
@objcMembers
public final class _VUIFConstantsObjC: NSObject {
    public class var subsystemName: String { VUIFConstants.subsystemName }
}

private final class _VUIFStub { }

public extension Bundle {
    static let virtualUIFoundation = Bundle(for: _VUIFStub.self)
}
