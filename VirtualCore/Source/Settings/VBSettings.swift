//
//  VBSettings.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: VBSettings.self))

public struct VBSettings: Hashable, Sendable {

    public static var current: VBSettings { VBSettingsContainer.current.settings }

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
    public var enableTSSCheck: Bool

    /// Show desktop picture from guest VM in thumbnails instead of the blur hash version.
    /// Currently not exposed in the UI.
    public var showDesktopPictureThumbnails: Bool

    /// Enables using the new ASIF format for boot disk images (requires macOS 26+ host).
    public var bootDiskImagesUseASIF: Bool

}

extension VBSettings {

    static let defaultUpdateChannel: AppUpdateChannel = .release
    static let defaultEnableTSSCheck = true
    static let defaultShowDesktopPictureThumbnails = false
    static let defaultBootDiskImagesUseASIF: Bool = {
        if #available(macOS 26, *) {
            true
        } else {
            false
        }
    }()

    init() {
        self.libraryURL = .defaultVirtualBuddyLibraryURL
        self.updateChannel = Self.defaultUpdateChannel
        self.enableTSSCheck = Self.defaultEnableTSSCheck
        self.showDesktopPictureThumbnails = Self.defaultShowDesktopPictureThumbnails
        self.bootDiskImagesUseASIF = Self.defaultBootDiskImagesUseASIF
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
        static let enableTSSCheck = "enableTSSCheck"
        static let showDesktopPictureThumbnails = "showDesktopPictureThumbnails"
        static let bootDiskImagesUseASIF = "bootDiskImagesUseASIF"
    }

    init(with defaults: UserDefaults) throws {
        defaults.register(defaults: [
            Keys.enableTSSCheck: Self.defaultEnableTSSCheck
        ])

        self.version = defaults.integer(forKey: Keys.version)
        self.enableTSSCheck = defaults.bool(forKey: Keys.enableTSSCheck)
        self.showDesktopPictureThumbnails = defaults.bool(forKey: Keys.showDesktopPictureThumbnails)
        self.bootDiskImagesUseASIF = defaults.bool(forKey: Keys.bootDiskImagesUseASIF)

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
        defaults.set(enableTSSCheck, forKey: Keys.enableTSSCheck)
        defaults.set(showDesktopPictureThumbnails, forKey: Keys.showDesktopPictureThumbnails)
        defaults.set(bootDiskImagesUseASIF, forKey: Keys.bootDiskImagesUseASIF)
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
