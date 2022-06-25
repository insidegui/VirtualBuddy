//
//  VirtualBuddyApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore

@main
struct VirtualBuddyApp: App {
    @NSApplicationDelegateAdaptor
    var appDelegate: VirtualBuddyAppDelegate

    @StateObject var settingsContainer = VBSettingsContainer.current
    @StateObject var updateController = SoftwareUpdateController.shared
    
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .onAppearOnce(perform: updateController.activate)
        }
        .windowToolbarStyle(.unified)
        .commands {
            #if ENABLE_SPARKLE
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates(nil)
                }
            }
            #endif
        }
        
        Settings {
            PreferencesView()
                .environmentObject(settingsContainer)
        }
    }
}
