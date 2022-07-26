import SwiftUI

public enum ControlGroupLevel: Int {
    case primary
    case secondary
}

public extension View {
    func controlGroup(cornerRadius: CGFloat = 10, level: ControlGroupLevel = .primary) -> some View {
        modifier(ControlGroupChrome(level: level, shapeBuilder: { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }))
    }

    func controlGroup<S>(_ shape: S, level: ControlGroupLevel = .primary) -> some View where S: InsettableShape {
        modifier(ControlGroupChrome<S>(level: level, shapeBuilder: { shape }))
    }
}

private struct ControlGroupChrome<Shape: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme)
    private var colorScheme

    var level: ControlGroupLevel
    var shapeBuilder: () -> Shape

    var dark: Bool { colorScheme == .dark }

    private var innerRimOpacity: Double {
        switch level {
        case .primary:
            return dark ? 0.15 : 0
        case .secondary:
            return dark ? 0.1 : 0
        }
    }

    private var outerRimOpacity: Double {
        switch level {
        case .primary:
            return dark ? 0.5 : 0.8
        case .secondary:
            return dark ? 0.4 : 0.7
        }
    }

    private var shadowOpacity: Double {
        switch level {
        case .primary:
            return dark ? 0.2 : 0.1
        case .secondary:
            return dark ? 0.1 : 0.05
        }
    }

    private var material: Material {
        switch level {
        case .primary:
            return .ultraThin
        case .secondary:
            return .thin
        }
    }

    func body(content: Content) -> some View {
        content
            .background(material, in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(innerRimOpacity), style: .init(lineWidth: 1))
                    .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(outerRimOpacity), radius: 1, x: 0, y: 0)
            .shadow(color: Color.black.opacity(shadowOpacity), radius: dark ? 8 : 10, x: 0, y: 0)
            .unfocusOnTap()
    }

    private var shape: Shape {
        shapeBuilder()
    }
}

#if DEBUG
struct ControlGroupChrome_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Primary Group")

            VStack {
                Text("Secondary Group")
            }
            .padding()
            .controlGroup(level: .secondary)
        }
        .padding(30)
        .controlGroup()
        .padding(50)
    }
}
#endif
