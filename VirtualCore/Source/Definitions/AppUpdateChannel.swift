//
//  AppUpdateChannel.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 25/06/22.
//

import Foundation

public struct AppUpdateChannel: Identifiable, Hashable {
    public var id: String { name.lowercased() }
    public let name: String
    public let appCastURL: URL

    public static let release = AppUpdateChannel(
        name: "Release",
        appCastURL: URL(string: "https://su.virtualbuddy.app/appcast.xml?channel=release")!
    )

    public static let beta = AppUpdateChannel(
        name: "Beta",
        appCastURL: URL(string: "https://su.virtualbuddy.app/appcast.xml?channel=beta")!
    )

    public static let byID: [AppUpdateChannel.ID: AppUpdateChannel] = [
        AppUpdateChannel.release.id: AppUpdateChannel.release,
        AppUpdateChannel.beta.id: AppUpdateChannel.beta
    ]
}
