#if DEBUG

import Foundation

public extension ProcessInfo {
    
    @objc static let isSwiftUIPreview: Bool = {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }()
    
}

public extension VBVirtualMachine {
    static let preview: VBVirtualMachine =  {
        try! VBVirtualMachine(bundleURL: Bundle.virtualCore.url(forResource: "Preview", withExtension: "vbvm")!)
    }()
}

#endif
