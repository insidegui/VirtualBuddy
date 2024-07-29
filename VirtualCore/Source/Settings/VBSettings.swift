//
//  VBSettings.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: VBSettings.self))

public struct VBSettings: Hashable {

    public static let updateChannelDidChangeNotification = Notification.Name("VBSettingsUpdateChannelDidChangeNotification")

    public static let currentVersion = 3

    public var version: Int = Self.currentVersion
    public var libraryURL: URL
    public var updateChannel: AppUpdateChannel {
        didSet {
            guard updateChannel != oldValue else { return }
            NotificationCenter.default.post(name: Self.updateChannelDidChangeNotification, object: updateChannel)
        }
    }

}

extension VBSettings {

    init() {
        self.libraryURL = .defaultVirtualBuddyLibraryURL
        self.updateChannel = .release
    }

    private struct Keys {
        static let version = "version"
        static let libraryPath: String = {
            #if DEBUG
            return ProcessInfo.isSwiftUIPreview ? "libraryPath-preview" : "libraryPath"
            #else
            return "libraryPath"
            #endif
        }()
        static let updateChannel = "updateChannel"
    }

    init(with defaults: UserDefaults) throws {
        self.version = defaults.integer(forKey: Keys.version)

        if let path = defaults.string(forKey: Keys.libraryPath) {
            self.libraryURL = URL(fileURLWithPath: path)
        } else {
            if version == 2 || version == 1 {
                /// Default library folder changed in VBSettings version 3,
                /// so if we're decoding settings from a previous release without a
                /// library defined, use the old default, which may have user VMs in it.
                /// 
                /// There's a high chance this never gets hit because the legacy default folder is likely
                /// to be in user defaults, even if the user never changed it.
                self.libraryURL = ._legacyDefaultVirtualBuddyLibraryURLForMigrationOnly
            } else {
                self.libraryURL = .defaultVirtualBuddyLibraryURL
            }
        }

        if let appUpdateChannelID = defaults.string(forKey: Keys.updateChannel) {
            logger.debug("Found channel \(appUpdateChannelID, privacy: .public) in user defaults")

            let restoredChannel = AppUpdateChannel.channelsByID[appUpdateChannelID] ?? .release
            let defaultChannel = AppUpdateChannel.defaultChannel(for: .current)

            if restoredChannel == .release, defaultChannel != .release {
                logger.debug("Settings specify release channel, but current build is for \(defaultChannel, privacy: .public), setting channel to \(defaultChannel, privacy: .public)")

                self.updateChannel = defaultChannel
            } else {
                self.updateChannel = restoredChannel
            }
        } else {
            let defaultChannel = AppUpdateChannel.defaultChannel(for: .current)

            logger.debug("No channel set in preferences, using default channel \(defaultChannel, privacy: .public) for build type \(VBBuildType.current, privacy: .public)")

            self.updateChannel = defaultChannel
        }
    }

    func write(to defaults: UserDefaults) throws {
        defaults.set(version, forKey: Keys.version)
        defaults.set(libraryURL.path, forKey: Keys.libraryPath)
        defaults.set(updateChannel.id, forKey: Keys.updateChannel)
    }

}

public extension URL {
    static let _legacyDefaultVirtualBuddyLibraryURLForMigrationOnly: URL = {
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

    static let defaultVirtualBuddyLibraryURL: URL = {
        do {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let url = baseURL.appendingPathComponent("VirtualBuddy")

            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

            return url
        } catch {
            fatalError("VirtualBuddy is unable to write to your user's Library/Application Support directory, this is bad!")
        }
    }()
}
