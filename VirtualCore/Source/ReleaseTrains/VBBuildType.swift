import Foundation

/// Represents the type of app build, such as beta vs. release.
public enum VBBuildType: String, CaseIterable, CustomStringConvertible {
    case debug
    case betaDebug
    case release
    case betaRelease
    case devRelease
}

public extension VBBuildType {
    /// The current build type according to compile-time flags.
    static let current: VBBuildType = {
        #if BUILDING_DEV_RELEASE
        return .devRelease
        #elseif BETA && DEBUG
        return .betaDebug
        #elseif BETA
        return .betaRelease
        #elseif DEBUG
        return .debug
        #else
        return .release
        #endif
    }()

    /// A user-facing name for the build type, or `nil` if it's a regular release build.
    var name: String? {
        switch self {
        case .debug:
            #if PRIVATE_BUILD
            return "Private"
            #else
            return "Debug"
            #endif
        case .betaDebug:
            return "Beta Debug"
        case .release:
            return nil
        case .betaRelease:
            return "Beta"
        case .devRelease:
            return "Dev"
        }
    }

    var description: String { name ?? "Release" }
}

public extension Bundle {
    var vbBuildType: VBBuildType { .current }

    /// The build description, including build type, version, and build number.
    /// Example: "Beta 2.0 - 123"
    var vbBuildDescription: String {
        if let typeDescription = vbBuildType.name {
            return "\(typeDescription) \(vbShortVersionString) - \(vbBuild)"
        } else {
            return "\(vbShortVersionString) - \(vbBuild)"
        }
    }

    /// The full version description such as "VirtualBuddy (Beta 2.0 - 123)", or just "VirtualBuddy" for release builds.
    var vbFullVersionDescription: String {
        let appName = "VirtualBuddy"
        if vbBuildType.name != nil {
            return "\(appName) (\(vbBuildDescription))"
        } else {
            return appName
        }
    }
}
