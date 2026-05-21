import SwiftUI
import AppKit

/// Describes a material that can be used with `MaterialView` or other material-based modifiers.
///
/// This is used to encapsulate an ``AirVisualEffect`` and/or an ``AirGlass`` material so that
/// they can be easily described as inputs for a view that renders a material, in a platform and system version agnostic way.
///
/// The views and modifiers that work with ``AirMaterial`` automatically switch between the visual effect and glass
/// material depending upon system support and user configuration.
public struct AirMaterial: Sendable {
    public var visualEffect: AirVisualEffect?
    public var glassEffect: AirGlassEffect?

    public init(visualEffect: AirVisualEffect? = nil, glassEffect: AirGlassEffect? = nil) {
        self.visualEffect = visualEffect
        self.glassEffect = glassEffect
    }
}

// MARK: - Views

/// Wraps contents in `GlassEffectContainer` if supported by current OS.
///
/// - note: The content you provide must be wrapped in a view that defines identity for its children,
/// otherwise glass effect transitions won't work as expected.
/// You will typically wrap your content in an `HStack`, `VStack`, or `ZStack`.
public struct AirGlassEffectContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - Modifiers

public extension View {

    /// Applies an background that uses ``AirMaterial``.
    /// - Parameter material: The ``AirMaterial`` to be used, describing variants for visual effect, glass, or both.
    /// - Parameter shape: A shape defining the material background area.
    /// - Parameter enabled: Enable/disable material background.
    @ViewBuilder
    func _airMaterialBackground(_ material: AirMaterial, in shape: some InsettableShape = Rectangle(), enabled: Bool = true) -> some View {
        modifier(AirMaterialBackgroundModifier(enabled: enabled, material: material, shape: shape))
    }

    /// Applies an background that uses ``AirMaterial``.
    /// - Parameter visualEffect: The ``AirVisualEffect`` to be used when Liquid Glass is not supported, disabled, or not provided. May be `nil` to only render the background when glass is available and enabled.
    /// - Parameter glassEffect: The ``AirGlassEffect`` material to be used when Liquid Glass is supported and enabled. May be `nil` to always use the `visualEffect` instead.
    /// - Parameter shape: A shape defining the material background area.
    /// - Parameter enabled: Enable/disable material background.
    @ViewBuilder
    func airMaterialBackground(visualEffect: AirVisualEffect?, glassEffect: AirGlassEffect?, in shape: some InsettableShape = Rectangle(), enabled: Bool = true) -> some View {
        _airMaterialBackground(.init(visualEffect: visualEffect, glassEffect: glassEffect), in: shape, enabled: enabled)
    }

    /// Applies the `glassEffectID` modifier if supported.
    func airGlassEffectID<ID>(_ id: ID?, in namespace: Namespace.ID) -> some View where ID: Hashable & Sendable {
        modifier(AirMaterialGlassIDModifier(id: id, namespace: namespace))
    }

    func airGlassEffectUnion<ID>(_ id: ID?, in namespace: Namespace.ID) -> some View where ID: Hashable & Sendable {
        modifier(AirMaterialGlassUnionModifier(id: id, namespace: namespace))
    }

}

private struct AirMaterialBackgroundModifier<ClipShape: InsettableShape>: ViewModifier {
    var enabled: Bool = true
    var material: AirMaterial
    var shape: ClipShape

    @Environment(\.isLiquidGlassSupported)
    private var glassEnabled

    func body(content: Content) -> some View {
        content
            .modifier { view in
                if enabled, let glass = material.glassEffect, #available(macOS 26, *), glassEnabled {
                    view.glassEffect(glass.systemGlass(), in: shape)
                } else if enabled, let visualEffect = material.visualEffect {
                    view.background { visualEffect.clippedView(in: shape) }
                } else {
                    view
                }
            }
    }

}

extension AirVisualEffect {
    /// A view that renders the pure visual effect, without rim or clipping.
    @ViewBuilder
    func materialView() -> some View {
        switch provider {
        case .AppKit(let material):
            MaterialView()
                .materialType(material)
                .materialBlendingMode(blendingMode)
                .materialState(state)
        case .SwiftUI(let material):
            Rectangle()
                .foregroundStyle(material)
        }

        if let tintColor = tintColor {
            tintColor
                .blendMode(.overlay)
                .colorSchemeOpacity(light: 0.9, dark: 0.7)

            tintColor
                .colorSchemeBlendMode(light: .plusDarker, dark: .plusLighter)
                .colorSchemeOpacity(light: 0.6, dark: 0.7)
        }
    }

    /// A view that renders the visual effect with a rim and clip shape.
    @ViewBuilder
    func clippedView(in shape: some InsettableShape) -> some View {
        ZStack {
            self
                .materialView()
                .rimEffect(in: shape)
        }
        .clipShape(shape)
    }
}

private struct AirMaterialGlassIDModifier<ID>: ViewModifier where ID: Hashable & Sendable {
    var id: ID?
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .modifier {
                if #available(macOS 26, *) {
                    $0.glassEffectID(id, in: namespace)
                } else {
                    $0
                }
            }
    }
}

private struct AirMaterialGlassUnionModifier<ID>: ViewModifier where ID: Hashable & Sendable {
    var id: ID?
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .modifier {
                if #available(macOS 26, *) {
                    $0.glassEffectUnion(id: id, namespace: namespace)
                } else {
                    $0
                }
            }
    }
}

// MARK: - Styles

struct AirMaterialButtonStyle: ButtonStyle {
    var visualEffect: AirVisualEffect?
    var glassEffect: AirGlassEffect?
    var shape: AnyInsettableShape

    init(visualEffect: AirVisualEffect? = nil, glassEffect: AirGlassEffect? = nil, shape: some InsettableShape) {
        self.visualEffect = visualEffect
        self.glassEffect = glassEffect
        self.shape = AnyInsettableShape(shape)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .overlay {
                Color.white
                    .opacity(configuration.isPressed ? 0.1 : 0)
                    .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .airMaterialBackground(visualEffect: visualEffect, glassEffect: glassEffect, in: shape)
    }
}

extension ButtonStyle where Self == AirMaterialButtonStyle {
    static func airMaterial(visualEffect: AirVisualEffect? = AirVisualEffect.menu, glassEffect: AirGlassEffect? = AirGlassEffect.regular, shape: some InsettableShape) -> AirMaterialButtonStyle {
        AirMaterialButtonStyle(visualEffect: visualEffect, glassEffect: glassEffect, shape: shape)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 32) {
        var vpad: Double { 32 }
        var hpad: Double { 12 }
        var shape: Capsule { Capsule(style: .continuous) }

        Group {
            Text("Visual Effect")
                .padding(.horizontal, vpad)
                .padding(.vertical, hpad)
                .airMaterialBackground(
                    visualEffect: .hudWindow,
                    glassEffect: nil,
                    in: shape
                )

            Text("Tinted Effect")
                .padding(.horizontal, vpad)
                .padding(.vertical, hpad)
                .airMaterialBackground(
                    visualEffect: .hudWindow.tint(.accentColor),
                    glassEffect: nil,
                    in: shape
                )

            Text("Regular Glass")
                .padding(.horizontal, vpad)
                .padding(.vertical, hpad)
                .airMaterialBackground(
                    visualEffect: nil,
                    glassEffect: .regular,
                    in: shape
                )

            Text("Clear Glass")
                .padding(.horizontal, vpad)
                .padding(.vertical, hpad)
                .airMaterialBackground(
                    visualEffect: nil,
                    glassEffect: .clear,
                    in: shape
                )

            Text("Tinted Glass")
                .padding(.horizontal, vpad)
                .padding(.vertical, hpad)
                .airMaterialBackground(
                    visualEffect: nil,
                    glassEffect: .clear.tint(.accentColor),
                    in: shape
                )
        }
        .font(.title2)
    }
    .padding(100)
    .previewWallpaper()
}
#endif
