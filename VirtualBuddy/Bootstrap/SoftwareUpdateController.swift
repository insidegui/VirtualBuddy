//
//  SoftwareUpdateController.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 25/06/22.
//

import Foundation
import VirtualCore

#if ENABLE_SPARKLE
import Sparkle
#endif

final class SoftwareUpdateController: NSObject, ObservableObject {

    static let shared = SoftwareUpdateController()

    private var settings: VBSettings { VBSettingsContainer.current.settings }

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
        updateController.startUpdater()
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        #if ENABLE_SPARKLE
        updateController.checkForUpdates(sender)
        #else
        let alert = NSAlert()
        alert.messageText = "Updating Disabled"
        alert.informativeText = "This build doesn't include Sparkle updates."
        alert.runModal()
        #endif
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
