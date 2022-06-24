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
    
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .windowToolbarStyle(.unified)
        
        Settings {
            PreferencesView()
                .environmentObject(settingsContainer)
        }
    }
}
