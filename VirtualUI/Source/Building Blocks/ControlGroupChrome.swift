import SwiftUI

public extension View {
    func controlGroup() -> some View {
        modifier(ControlGroupChrome())
    }
}

private struct ControlGroupChrome: ViewModifier {
    @Environment(\.colorScheme)
    private var colorScheme

    var dark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .background(Material.ultraThin, in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(dark ? 0.1 : 0), style: .init(lineWidth: 1))
                    .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(dark ? 0.5 : 0.8), radius: 1, x: 0, y: 0)
            .shadow(color: Color.black.opacity(dark ? 0.2 : 0.1), radius: dark ? 8 : 10, x: 0, y: 0)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
}

#if DEBUG
struct ControlGroupChrome_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("ABC")
            Text("DEF")
        }
        .padding()
        .controlGroup()
        .padding()
    }
}
#endif
