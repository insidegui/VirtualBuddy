import SwiftUI

public extension EnvironmentValues {
    #if DEBUG
    @Entry var preview_overrideLiquidGlassSupported: Bool? = nil
    #endif

    var isLiquidGlassSupported: Bool {
        guard #available(macOS 26.0, *) else { return false }

        #if DEBUG
        return preview_overrideLiquidGlassSupported ?? true
        #else
        return true
        #endif
    }
}
