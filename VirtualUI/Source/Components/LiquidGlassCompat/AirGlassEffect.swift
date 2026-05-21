import SwiftUI

/**
 Backwards-compatible Liquid Glass support.

 This file defines a bunch of types and modifiers that can be used to apply Liquid Glass
 effects in a backwards-compatible way without the need to check for OS version everywhere.
 */

/// Maps to glass style on macOS 26, does nothing on older versions.
public struct AirGlassEffect: Hashable, Sendable {
    private enum ID: String {
        case clear
        case regular
    }

    public enum Transition: Hashable, Sendable {
        case identity
        case matchedGeometry
        case materialize
    }

    private var id: ID
    private var isInteractive: Bool
    private var tintColor: Color?
}

public extension AirGlassEffect {
    static let clear = AirGlassEffect(id: .clear, isInteractive: false)
    static let regular = AirGlassEffect(id: .regular, isInteractive: false)

    init() {
        self.id = .regular
        self.isInteractive = false
        self.tintColor = nil
    }

    func interactive(_ isEnabled: Bool = true) -> AirGlassEffect {
        var mself = self
        mself.isInteractive = isEnabled
        return mself
    }

    func tint(_ color: Color? = nil) -> AirGlassEffect {
        var mself = self
        mself.tintColor = color
        return mself
    }
}

@available(macOS 26, *)
public extension AirGlassEffect {
    func systemGlass() -> Glass {
        let base: Glass = switch id {
        case .clear: .clear
        case .regular: .regular
        }

        return base
            .interactive(isInteractive)
            .tint(tintColor)
    }

    func systemAppKitGlass() -> NSGlassEffectView.Style {
        switch id {
        case .clear: .clear
        case .regular: .regular
        }
    }

    func systemAppKitTintColor() -> NSColor? {
        tintColor.flatMap { NSColor(cgColor: $0.resolve(in: EnvironmentValues()).cgColor) }
    }
}

@available(macOS 26, *)
public extension AirGlassEffect.Transition {
    var systemTransition: GlassEffectTransition {
        switch self {
        case .identity: .identity
        case .matchedGeometry: .matchedGeometry
        case .materialize: .materialize
        }
    }
}

// MARK: - Modifiers

public extension View {
    @ViewBuilder
    func airGlassEffect(_ glass: AirGlassEffect = .regular, in shape: some Shape = Capsule(style: .continuous)) -> some View {
        if #available(macOS 26, *) {
            glassEffect(glass.systemGlass(), in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func airGlassEffectTransition(_ transition: AirGlassEffect.Transition) -> some View {
        if #available(macOS 26, *) {
            glassEffectTransition(transition.systemTransition)
        } else {
            self
        }
    }
}

// MARK: - Button Styles

private struct AirGlassButtonStyleModifier<FallbackStyle>: ViewModifier where FallbackStyle: ButtonStyle {
    var prominent: Bool
    var fallback: FallbackStyle

    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

    func body(content: Content) -> some View {
        if #available(macOS 26, *), isLiquidGlassSupported {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(fallback)
        }
    }
}

/// Exactly the same implementation as `AirGlassButtonStyleModifier`, but need this to allow for `PrimitiveButtonStyle` to be used as fallback.
private struct AirGlassPrimitiveButtonStyleModifier<FallbackStyle>: ViewModifier where FallbackStyle: PrimitiveButtonStyle {
    var prominent: Bool
    var fallback: FallbackStyle

    @Environment(\.isLiquidGlassSupported)
    private var isLiquidGlassSupported

    func body(content: Content) -> some View {
        if #available(macOS 26, *), isLiquidGlassSupported {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(fallback)
        }
    }
}

public extension View {
    func airGlassButtonStyle(prominent: Bool = false, fallback: some ButtonStyle) -> some View {
        modifier(AirGlassButtonStyleModifier(prominent: prominent, fallback: fallback))
    }

    @ViewBuilder
    func airGlassButtonStyle(prominent: Bool = false, fallback: some PrimitiveButtonStyle) -> some View {
        modifier(AirGlassPrimitiveButtonStyleModifier(prominent: prominent, fallback: fallback))
    }

    @ViewBuilder
    func airGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(AirGlassPrimitiveButtonStyleModifier(prominent: prominent, fallback: DefaultButtonStyle()))
    }
}
