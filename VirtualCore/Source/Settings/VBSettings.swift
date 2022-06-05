//
//  VBSettings.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation

public struct VBSettings: Hashable {

    public static let currentVersion = 1

    public var version: Int = Self.currentVersion
    public var libraryURL: URL

}

extension VBSettings {

    init() {
        self.libraryURL = .defaultVirtualBuddyLibraryURL
    }

    private struct Keys {
        static let version = "version"
        static let libraryPath = "libraryPath"
    }

    init(with defaults: UserDefaults) throws {
        self.version = defaults.integer(forKey: Keys.version)

        if let path = defaults.string(forKey: Keys.libraryPath) {
            self.libraryURL = URL(fileURLWithPath: path)
        } else {
            self.libraryURL = .defaultVirtualBuddyLibraryURL
        }
    }

    func write(to defaults: UserDefaults) throws {
        defaults.set(version, forKey: Keys.version)
        defaults.set(libraryURL.path, forKey: Keys.libraryPath)
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
