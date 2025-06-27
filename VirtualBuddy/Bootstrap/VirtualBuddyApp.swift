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

struct VirtualBuddyApp: App {
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
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    UILog("OPEN URL \(url.path(percentEncoded: false))")

                    sessionManager.open(fileURL: url, library: library)
                }
                .environment(\.openVirtualBuddySettings, appDelegate.openSettingsAction)
                .background { TransparentWindowTitleBarView() }
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

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openSettingsAction()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

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
        .handlesExternalEvents(matching: ["*"])
    }
}

// TODO: Remove this after moving to AppKit lifecycle
private struct TransparentWindowTitleBarView: NSViewRepresentable {
    typealias NSViewType = _MakeWindowTitleBarTransparentView

    func makeNSView(context: Context) -> _MakeWindowTitleBarTransparentView {
        _MakeWindowTitleBarTransparentView(frame: .zero)
    }

    func updateNSView(_ nsView: _MakeWindowTitleBarTransparentView, context: Context) {

    }

    final class _MakeWindowTitleBarTransparentView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            
            window?.titlebarAppearsTransparent = true
        }
    }
}
