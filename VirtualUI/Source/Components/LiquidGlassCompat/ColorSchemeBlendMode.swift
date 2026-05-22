import SwiftUI

public extension View {
    
    /// Applies a different blend mode depending upon the current environment's color scheme.
    func colorSchemeBlendMode(light: BlendMode, dark: BlendMode) -> some View {
        modifier(ColorSchemeBlendMode(lightBlendMode: light, darkBlendMode: dark))
    }
    
}

private struct ColorSchemeBlendMode: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    
    let lightBlendMode: BlendMode
    let darkBlendMode: BlendMode
    
    private var currentBlendMode: BlendMode {
        switch colorScheme {
        case .light:
            return lightBlendMode
        case .dark:
            return darkBlendMode
        @unknown default:
            return lightBlendMode
        }
    }
    
    func body(content: Content) -> some View {
        content
            .blendMode(currentBlendMode)
    }
    
}
