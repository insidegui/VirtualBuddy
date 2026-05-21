import SwiftUI

extension EnvironmentValues {
    @Entry fileprivate(set) var rimEffectColor = Color.white
    @Entry fileprivate(set) var rimEffectOpacity = 0.25
    @Entry fileprivate(set) var rimEffectBlendMode = BlendMode.plusLighter
    @Entry fileprivate(set) var rimEffectAngle = Angle.degrees(60)
    @Entry fileprivate(set) var rimEffectShape = AnyInsettableShape(ContainerRelativeShape())
    @Entry fileprivate(set) var rimEffectThickness = 1.0
    @Entry fileprivate(set) var rimEffectDisabled = false
}

private struct RimEffectModifier: ViewModifier {
    @Environment(\.rimEffectColor)
    private var color

    @Environment(\.rimEffectOpacity)
    private var opacity

    @Environment(\.rimEffectBlendMode)
    private var blendMode

    @Environment(\.rimEffectAngle)
    private var angle

    @Environment(\.rimEffectShape)
    private var shape

    @Environment(\.rimEffectThickness)
    private var thickness

    @Environment(\.rimEffectDisabled)
    private var disabled

    func body(content: Content) -> some View {
        content
            .overlay { rim.opacity(disabled ? 0 : 1) }
    }

    @ViewBuilder
    private var rim: some View {
        AngularGradient(
            stops: [
                .init(color: color, location: -0.2),
                .init(color: color.opacity(0.5), location: 0.3),
                .init(color: color, location: 0.5),
                .init(color: color.opacity(0.5), location: 0.7),
                .init(color: color, location: 1.2),
            ],
            center: .center,
            angle: angle
        )
        .visualEffect { content, _ in
            content.blur(radius: 5)
        }
        .clipShape(shape.rim(thickness: thickness))
        .blendMode(blendMode)
        .opacity(opacity)
        .clipShape(shape)
    }
}

public extension View {
    func rimEffect(in shape: some InsettableShape) -> some View {
        modifier(RimEffectModifier())
            .environment(\.rimEffectShape, AnyInsettableShape(shape))
    }

    func rimEffectColor(_ color: Color) -> some View {
        environment(\.rimEffectColor, color)
    }

    func rimEffectOpacity(_ opacity: Double) -> some View {
        environment(\.rimEffectOpacity, opacity)
    }

    func rimEffectDisabled(_ disabled: Bool = true) -> some View {
        environment(\.rimEffectDisabled, disabled)
    }

    func rimEffectBlendMode(_ blendMode: BlendMode) -> some View {
        environment(\.rimEffectBlendMode, blendMode)
    }

    func rimEffectAngle(_ angle: Angle) -> some View {
        environment(\.rimEffectAngle, angle)
    }

    func rimEffectThickness(_ thickness: Double) -> some View {
        environment(\.rimEffectThickness, thickness)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Basic") {
    Capsule()
        .fill(Color.indigo)
        .frame(width: 160, height: 80)
        .rimEffect(in: Capsule())
        .padding(100)
        .background(Color.gray)
}

#Preview("Material") {
    Capsule()
        .fill(.thickMaterial)
        .frame(width: 160, height: 80)
        .rimEffect(in: Capsule())
        .padding(100)
        .previewWallpaper()
}

#Preview("Animation") {
    @Previewable @State var animated = false

    Capsule()
        .fill(.thickMaterial)
        .frame(width: 160, height: 80)
        .rimEffect(in: Capsule())
        .padding(100)
        .previewWallpaper()
        .rimEffectAngle(animated ? Angle.degrees(359.9) : Angle.degrees(0))
        .rimEffectOpacity(animated ? 0.25 : 0)
        .rimEffectThickness(2)
        .onTapGesture {
            withAnimation(.default) {
                animated.toggle()
            }
        }
        .overlay(alignment: .bottom) {
            Text("Click To Animate")
                .foregroundStyle(.white)
                .font(.footnote)
                .padding(.bottom)
        }
}
#endif
