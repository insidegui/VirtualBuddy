#if DEBUG

import SwiftUI

public extension ProcessInfo {
    
    @objc static let isSwiftUIPreview: Bool = {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }()
    
}

#endif
