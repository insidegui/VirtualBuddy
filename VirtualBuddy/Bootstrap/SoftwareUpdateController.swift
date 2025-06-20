//
//  SoftwareUpdateController.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 25/06/22.
//

import SwiftUI
import VirtualCore
import OSLog

#if ENABLE_SPARKLE
import Sparkle
#endif

final class SoftwareUpdateController: NSObject, ObservableObject {

    private let logger = Logger(subsystem: kShellAppSubsystem, category: "SoftwareUpdateController")

    static let shared = SoftwareUpdateController()

    private var settings: VBSettings { VBSettingsContainer.current.settings }

    @Published var automaticUpdatesEnabled = true {
        didSet {
            #if ENABLE_SPARKLE
            guard automaticUpdatesEnabled != oldValue else { return }

            logger.debug("Setting \(#function, privacy: .public) to \(self.automaticUpdatesEnabled, privacy: .public)")

            updateController.updater.automaticallyChecksForUpdates = automaticUpdatesEnabled
            #endif
        }
    }

    var automaticUpdatesBinding: Binding<Bool> {
        Binding { [self] in
            automaticUpdatesEnabled
        } set: { [self] newValue in
            automaticUpdatesEnabled = newValue
        }
    }

    #if ENABLE_SPARKLE
    private lazy var updateController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()
    #endif

    func activate() {
        #if ENABLE_SPARKLE
        logger.debug(#function)

        updateController.startUpdater()
        automaticUpdatesEnabled = updateController.updater.automaticallyChecksForUpdates
        registerForUpdateChannelChanges()
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if ENABLE_SPARKLE
        logger.debug(#function)
        
        updateController.checkForUpdates(sender)
        #else
        let alert = NSAlert()
        alert.messageText = "Updating Disabled"
        alert.informativeText = "This build doesn't include Sparkle updates."
        alert.runModal()
        #endif
    }

    private func registerForUpdateChannelChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateChannelChanged),
            name: VBSettings.updateChannelDidChangeNotification,
            object: nil
        )
    }

    /// Check for updates when switching from release to beta channel.
    @objc private func handleUpdateChannelChanged(_ note: Notification) {
        guard let channel = note.object as? AppUpdateChannel else { return }
        guard channel != .release else { return }

        checkForUpdates(nil)
    }

}

#if ENABLE_SPARKLE
extension SoftwareUpdateController: SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    func feedURLString(for updater: SPUUpdater) -> String? {
        settings.updateChannel.appCastURL.absoluteString
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        [settings.updateChannel.id]
    }

}
#endif
