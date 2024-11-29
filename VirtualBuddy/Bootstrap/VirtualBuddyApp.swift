//
//  VirtualBuddyApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualUI
@_spi(GuestEnvironment) import VirtualCore

let kShellAppSubsystem = "codes.rambo.VirtualBuddy"

@main
struct VirtualBuddyApp: App {
    init() {
        ProcessInfo._isVirtualBuddyHost.withLock { $0 = true }
        ProcessInfo._isVirtualBuddyGuest.withLock { $0 = false }
    }

    @NSApplicationDelegateAdaptor
    var appDelegate: VirtualBuddyAppDelegate

    private var settingsContainer: VBSettingsContainer { appDelegate.settingsContainer }
    private var updateController: SoftwareUpdateController { appDelegate.updateController }
    private var library: VMLibraryController { appDelegate.library }
    private var sessionManager: VirtualMachineSessionUIManager { appDelegate.sessionManager }

    @Environment(\.openWindow)
    private var openWindow

    @StateObject private var updatesController = SoftwareUpdateController.shared

    private let mainWindowTitle: String = Bundle.main.vbFullVersionDescription

    var body: some Scene {
        Window(Text(mainWindowTitle), id: .vb_libraryWindowID) {
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

            CommandGroup(after: .windowArrangement) {
                Button("Library") {
                    openWindow(id: .vb_libraryWindowID)
                }
                .keyboardShortcut(KeyEquivalent("0"), modifiers: .command)
            }
        }
        
        Settings {
            PreferencesView(deepLinkSentinel: DeepLinkHandler.shared.sentinel, enableAutomaticUpdates: $updatesController.automaticUpdatesEnabled)
                .environmentObject(settingsContainer)
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 370, maxHeight: .infinity)
        }

        #if DEBUG
        Window(Text("Guest Simulator"), id: .vb_simulatorWindowID) {
            GuestSimulatorScreen()
        }
        #endif // debug
    }
}
