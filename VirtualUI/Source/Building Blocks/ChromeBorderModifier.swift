import SwiftUI

extension View {
    func chromeBorder(radius: CGFloat, highlightEnabled: Bool = true, rimEnabled: Bool = true, shadowEnabled: Bool = true, highlightIntensity: Double = 0.5) -> some View {
        chromeBorder(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), highlightEnabled: highlightEnabled, rimEnabled: rimEnabled, shadowEnabled: shadowEnabled, highlightIntensity: highlightIntensity)
    }

    func chromeBorder<BorderShape: InsettableShape>(shape: BorderShape, highlightEnabled: Bool = true, rimEnabled: Bool = true, shadowEnabled: Bool = true, highlightIntensity: Double = 0.5) -> some View {
        modifier(ChromeBorderModifier(shape: shape, highlightEnabled: highlightEnabled, rimEnabled: rimEnabled, shadowEnabled: shadowEnabled, highlightIntensity: highlightIntensity))
    }
}

private struct ChromeBorderModifier<BorderShape: InsettableShape>: ViewModifier {
    var shape: BorderShape
    var highlightEnabled = true
    var rimEnabled = true
    var shadowEnabled = true
    var highlightIntensity = 0.5

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(shadowEnabled ? 0.2 : 0), radius: 6, x: 0, y: 0)
            .shadow(color: .black.opacity(rimEnabled ? 0.5 : 0), radius: 1, x: 0, y: 0)
            .overlay {
                if highlightEnabled {
                    ZStack {
                        shape
                            .strokeBorder(Color.white, lineWidth: 1)

                        LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .blendMode(.plusLighter)
                    .opacity(highlightIntensity)
                }
            }
    }
}
