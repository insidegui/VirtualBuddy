//
//  VBSettings.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation

public struct VBSettings: Hashable {

    public static let currentVersion = 2

    public var version: Int = Self.currentVersion
    public var libraryURL: URL
    public var updateChannel: AppUpdateChannel

}

extension VBSettings {

    init() {
        self.libraryURL = .defaultVirtualBuddyLibraryURL
        self.updateChannel = .release
    }

    private struct Keys {
        static let version = "version"
        static let libraryPath = "libraryPath"
        static let updateChannel = "updateChannel"
    }

    init(with defaults: UserDefaults) throws {
        self.version = defaults.integer(forKey: Keys.version)

        if let path = defaults.string(forKey: Keys.libraryPath) {
            self.libraryURL = URL(fileURLWithPath: path)
        } else {
            self.libraryURL = .defaultVirtualBuddyLibraryURL
        }

        if let appUpdateChannelID = defaults.string(forKey: Keys.updateChannel) {
            self.updateChannel = AppUpdateChannel.byID[appUpdateChannelID] ?? .release
        } else {
            self.updateChannel = .release
        }
    }

    func write(to defaults: UserDefaults) throws {
        defaults.set(version, forKey: Keys.version)
        defaults.set(libraryURL.path, forKey: Keys.libraryPath)
        defaults.set(updateChannel.id, forKey: Keys.updateChannel)
    }

}

public extension URL {
    static let defaultVirtualBuddyLibraryURL: URL = {
        do {
            let baseURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            return baseURL
                .appendingPathComponent("VirtualBuddy")
        } catch {
            fatalError("VirtualBuddy is unable to write to your user's documents directory, this is bad!")
        }
    }()
}
