import SwiftUI

public extension View {

    /// Applies a different opacity depending upon the current environment's color scheme.
    func colorSchemeOpacity(light: Double, dark: Double) -> some View {
        modifier(ColorSchemeOpacity(lightOpacity: light, darkOpacity: dark))
    }

}

private struct ColorSchemeOpacity: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    let lightOpacity: Double
    let darkOpacity: Double

    private var currentOpacity: Double {
        switch colorScheme {
        case .light:
            return lightOpacity
        case .dark:
            return darkOpacity
        @unknown default:
            return lightOpacity
        }
    }

    func body(content: Content) -> some View {
        content.opacity(currentOpacity)
    }

}
