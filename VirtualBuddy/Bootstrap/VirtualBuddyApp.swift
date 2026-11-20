//
//  VirtualBuddyApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore
import VirtualUI
import OSLog

let kShellAppSubsystem = "codes.rambo.VirtualBuddy"
private let logger = Logger(subsystem: kShellAppSubsystem, category: "VirtualBuddyApp")

struct VirtualBuddyApp: App {
    @NSApplicationDelegateAdaptor
    var appDelegate: VirtualBuddyAppDelegate

    private var settingsContainer: VBSettingsContainer { appDelegate.settingsContainer }
    private var library: VMLibraryController { appDelegate.library }
    private var sessionManager: VirtualMachineSessionUIManager { appDelegate.sessionManager }

    @Environment(\.openWindow)
    private var openWindow

    @StateObject private var updateController = SoftwareUpdateController.shared

    private let mainWindowTitle: String = Bundle.main.vbFullVersionDescription

    var body: some Scene {
        Window(Text(mainWindowTitle), id: .vb_libraryWindowID) {
            LibraryView()
                .onAppearOnce(perform: updateController.activate)
                .environmentObject(library)
                .environmentObject(sessionManager)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    logger.debug("OPEN URL \(url.path(percentEncoded: false), privacy: .public)")

                    sessionManager.open(fileURL: url, library: library)
                }
                .background { TransparentWindowTitleBarView() }
                .onReceive(NotificationCenter.default.publisher(for: .openVirtualBuddyLibraryWindow)) { _ in
                    openLibraryWindow()
                }
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

            CommandMenu("Guest") {
                VirtualMachineGuestCommands()
                    .environmentObject(sessionManager)
            }

            CommandGroup(before: .windowSize) {
                VirtualMachineWindowCommands()
                    .environmentObject(sessionManager)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Library") {
                    openLibraryWindow()
                }
                .keyboardShortcut(KeyEquivalent("0"), modifiers: .command)
            }
        }
        .handlesExternalEvents(matching: ["*"])

        Settings {
            SettingsScreen(
                enableAutomaticUpdates: $updateController.automaticUpdatesEnabled,
                deepLinkSentinel: DeepLinkHandler.shared.sentinel
            )
            .environmentObject(settingsContainer)
        }
        .windowResizability(.contentSize)
    }

    private func openLibraryWindow() {
        openWindow(id: .vb_libraryWindowID)
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
