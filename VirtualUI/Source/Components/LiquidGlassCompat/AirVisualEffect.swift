import SwiftUI
import AppKit

public typealias MaterialType = NSVisualEffectView.Material
public typealias MaterialBlendingMode = NSVisualEffectView.BlendingMode
public typealias MaterialState = NSVisualEffectView.State

public extension MaterialType {
    /// The default background type used for ``AirVisualEffect``.
    static let `default` = MaterialType.popover
}

/// Maps to traditional `NSVisualEffectView` style or SwiftUI `Material`, works similarly to ``AirGlassEffect``.
public struct AirVisualEffect: Sendable {
    /// Determines how the effect renders its material.
    enum MaterialProvider {
        /// The effect renders its material using an AppKit material with `NSVisualEffectView` under the hood.
        case AppKit(_ material: MaterialType)

        /// The effect renders its material using the SwiftUI `Material`.
        case SwiftUI(_ material: SwiftUI.Material)
    }

    var provider: MaterialProvider
    public private(set) var blendingMode: MaterialBlendingMode = .withinWindow
    public private(set) var state: MaterialState = .active
    public private(set) var tintColor: Color? = nil
    public private(set) var material: SwiftUI.Material? = nil
}

public extension AirVisualEffect {
    static let titlebar = AirVisualEffect(id: MaterialType.titlebar)
    static let selection = AirVisualEffect(id: MaterialType.selection)
    static let menu = AirVisualEffect(id: MaterialType.menu)
    static let popover = AirVisualEffect(id: MaterialType.popover)
    static let sidebar = AirVisualEffect(id: MaterialType.sidebar)
    static let headerView = AirVisualEffect(id: MaterialType.headerView)
    static let sheet = AirVisualEffect(id: MaterialType.sheet)
    static let windowBackground = AirVisualEffect(id: MaterialType.windowBackground)
    static let hudWindow = AirVisualEffect(id: MaterialType.hudWindow)
    static let fullScreenUI = AirVisualEffect(id: MaterialType.fullScreenUI)
    static let toolTip = AirVisualEffect(id: MaterialType.toolTip)
    static let contentBackground = AirVisualEffect(id: MaterialType.contentBackground)
    static let underWindowBackground = AirVisualEffect(id: MaterialType.underWindowBackground)
    static let underPageBackground = AirVisualEffect(id: MaterialType.underPageBackground)

    /// Returns the system material if the visual effect is configured to use an AppKit material.
    var systemMaterial: MaterialType {
        switch provider {
        case .AppKit(let material):
            return material
        case .SwiftUI:
            assertionFailure("A client of \(String(describing: type(of: self))) is attempting to read systemMaterial for a visual effect that's configured to use an AppKit material")
            return .default
        }
    }

    static func material(_ material: SwiftUI.Material) -> AirVisualEffect {
        AirVisualEffect(material)
    }

    init() {
        self.provider = .SwiftUI(.regular)
        self.blendingMode = .withinWindow
        self.state = .active
    }

    init(id: MaterialType) {
        self.provider = .AppKit(id)
    }

    init(_ material: SwiftUI.Material) {
        self.provider = .SwiftUI(material)
    }

    func blendingMode(_ blendingMode: MaterialBlendingMode) -> AirVisualEffect {
        var mself = self
        mself.blendingMode = blendingMode
        return mself
    }

    func state(_ state: MaterialState) -> AirVisualEffect {
        var mself = self
        mself.state = state
        return mself
    }

    func tint(_ color: Color? = nil) -> AirVisualEffect {
        var mself = self
        mself.tintColor = color
        return mself
    }
}

// MARK: - Convenience

public extension MaterialBlendingMode {

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
