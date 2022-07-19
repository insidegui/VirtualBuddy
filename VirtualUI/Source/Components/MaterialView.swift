//
//  MaterialView.swift
//  AirUI
//
//  Created by Guilherme Rambo on 16/03/22.
//

import SwiftUI

typealias MaterialType = NSVisualEffectView.Material
typealias MaterialBlendingMode = NSVisualEffectView.BlendingMode
typealias MaterialState = NSVisualEffectView.State

extension MaterialBlendingMode {
    
    /// Uses within window blending mode when running in SwiftUI previews,
    /// but the behind window blending mode when running normally.
    /// Does not affect release builds, which always return `.behindWindow`.
    static var behindWindowForPreviews: Self {
        #if DEBUG
        if ProcessInfo.isSwiftUIPreview {
            return .withinWindow
        } else {
            return .behindWindow
        }
        #else
        return .behindWindow
        #endif
    }
    
}

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

extension View {
    
    /// Applies a background material to the view, clipped to the specified shape.
    /// - Parameters:
    ///   - type: The type of material to be used. Will use the material from the current environment if `nil`.
    ///   - blendMode: The material blending mode. Will use the blending mode from the current environment if `nil`.
    ///   - state: The material state. Will use the state from the current environment if `nil`.
    ///   - shape: The shape clipping the material.
    /// - Returns: The modified view.
    func materialBackground<S>(_ type: MaterialType? = nil,
                               blendMode: MaterialBlendingMode? = nil,
                               state: MaterialState? = nil,
                               in shape: S) -> some View where S: Shape
    {
        background(
            MaterialView()
                .clipShape(shape)
                .materialType(type)
                .materialBlendingMode(blendMode)
                .materialState(state)
        )
    }
    
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

fileprivate struct MaterialViewStateKey: EnvironmentKey {
    static var defaultValue: MaterialState = .active
}

fileprivate struct MaterialViewBlendingModeKey: EnvironmentKey {
    static var defaultValue: MaterialBlendingMode = .withinWindow
}

fileprivate struct MaterialViewMaterialKey: EnvironmentKey {
    static var defaultValue: MaterialType = .popover
}

fileprivate extension EnvironmentValues {
    
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
