import SwiftUI

/// Underlying implementation for ``AirVisualEffect`` when used via custom modifiers.
///
/// - note: Avoid using this view directly, use the `airMaterialBackground` modifier instead.
struct MaterialView: NSViewRepresentable {
    
    typealias NSViewType = NSVisualEffectView

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(frame: .zero)
        
        v.material = context.environment.materialType
        v.blendingMode = context.environment.materialBlendingMode
        v.state = context.environment.materialState
        
        return v
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if (nsView.material != context.environment.materialType) {
            nsView.material = context.environment.materialType
        }
        if (nsView.blendingMode != context.environment.materialBlendingMode) {
            nsView.blendingMode = context.environment.materialBlendingMode
        }
        if context.environment.accessibilityReduceTransparency {
            nsView.state = .inactive
        } else {
            if (nsView.state != context.environment.materialState) {
                nsView.state = context.environment.materialState
            }
        }
    }
    
}

// MARK: - Environment

extension View {

    @ViewBuilder
    func materialType(_ material: MaterialType?) -> some View {
        if let material = material {
            environment(\.materialType, material)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func materialBlendingMode(_ mode: MaterialBlendingMode?) -> some View {
        if let mode = mode {
            environment(\.materialBlendingMode, mode)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func materialState(_ state: MaterialState?) -> some View {
        if let state = state {
            environment(\.materialState, state)
        } else {
            self
        }
    }
    
}

private struct MaterialViewStateKey: EnvironmentKey {
    static var defaultValue: MaterialState = .active
}

private struct MaterialViewBlendingModeKey: EnvironmentKey {
    static var defaultValue: MaterialBlendingMode = .withinWindow
}

private struct MaterialViewMaterialKey: EnvironmentKey {
    static var defaultValue: MaterialType = .popover
}

private extension EnvironmentValues {
    
    var materialState: MaterialState {
        get { self[MaterialViewStateKey.self] }
        set { self[MaterialViewStateKey.self] = newValue }
    }
    
    var materialType: MaterialType {
        get { self[MaterialViewMaterialKey.self] }
        set { self[MaterialViewMaterialKey.self] = newValue }
    }
    
    var materialBlendingMode: MaterialBlendingMode {
        get { self[MaterialViewBlendingModeKey.self] }
        set { self[MaterialViewBlendingModeKey.self] = newValue }
    }
    
}
