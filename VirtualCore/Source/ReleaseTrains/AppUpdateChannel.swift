//
//  AppUpdateChannel.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 25/06/22.
//

import Foundation

public struct AppUpdateChannel: Identifiable, Hashable, CustomStringConvertible {
    public var id: String { name.lowercased() }
    public let name: String
    public let appCastURL: URL
}

public extension AppUpdateChannel {
    static let release = AppUpdateChannel(
        name: "Release",
        appCastURL: URL(string: "https://su.virtualbuddy.app/appcast.xml?channel=release")!
    )

    static let beta = AppUpdateChannel(
        name: "Beta",
        appCastURL: URL(string: "https://su.virtualbuddy.app/appcast.xml?channel=beta")!
    )

    static let channelsByID: [AppUpdateChannel.ID: AppUpdateChannel] = [
        AppUpdateChannel.release.id: AppUpdateChannel.release,
        AppUpdateChannel.beta.id: AppUpdateChannel.beta
    ]

    static func defaultChannel(for buildType: VBBuildType) -> AppUpdateChannel {
        switch buildType {
        case .debug, .devRelease, .release:
            return .release
        case .betaDebug, .betaRelease:
            return .beta
        }
    }
}

public extension AppUpdateChannel {
    var description: String { id }
}
