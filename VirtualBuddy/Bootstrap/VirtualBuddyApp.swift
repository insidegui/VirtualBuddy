//
//  VirtualBuddyApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore
import VirtualUI

@main
struct VirtualBuddyApp: App {
    @NSApplicationDelegateAdaptor
    var appDelegate: VirtualBuddyAppDelegate

    @StateObject private var settingsContainer = VBSettingsContainer.current
    @StateObject private var updateController = SoftwareUpdateController.shared
    @StateObject private var library = VMLibraryController.shared
    @StateObject private var sessionManager = VirtualMachineSessionUIManager.shared

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .onAppearOnce(perform: updateController.activate)
                .environmentObject(library)
                .environmentObject(sessionManager)
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

            CommandGroup(before: .windowSize) {
                VirtualMachineWindowCommands()
                    .environmentObject(sessionManager)
            }
        }
        
        Settings {
            PreferencesView()
                .environmentObject(settingsContainer)
        }
    }
}
