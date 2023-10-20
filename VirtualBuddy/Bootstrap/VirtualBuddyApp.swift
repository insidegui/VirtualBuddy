//
//  VirtualBuddyApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore
import VirtualUI

let kShellAppSubsystem = "codes.rambo.VirtualBuddy"

@main
struct VirtualBuddyApp: App {
    @NSApplicationDelegateAdaptor
    var appDelegate: VirtualBuddyAppDelegate

    @StateObject private var settingsContainer = VBSettingsContainer.current
    @StateObject private var updateController = SoftwareUpdateController.shared
    @StateObject private var library = VMLibraryController.shared
    @StateObject private var sessionManager = VirtualMachineSessionUIManager.shared

    @Environment(\.openCocoaWindow)
    private var openWindow

    var body: some Scene {
        WindowGroup(id: "library") {
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
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        }
    }
}
