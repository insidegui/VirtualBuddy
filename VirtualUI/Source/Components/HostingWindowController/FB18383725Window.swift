//
//  FB18383725Window.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 25/6/25.
//

import SwiftUI
import Combine
import BuddyKit

/// Implements a workaround for a crash that occurs in macOS 26 when built with the macOS 26 SDK.
class FB18383725Window: NSWindow {
    private var toolbarToRestoreAfterFullScreenTransition: NSToolbar?

    private var cancellables = Set<AnyCancellable>()

    override func toggleFullScreen(_ sender: Any?) {
        guard #available(macOS 26, *) else {
            return super.toggleFullScreen(sender)
        }

        /**
         Filed as `FB18383725`.

         Really ugly hack to work around a crash in macOS 26 when built with the macOS 26 SDK.
         The crash occurs when the window content is an `NSHostingController` and the root view has a `toolbar` modifier:

         ```
         *** Terminating app due to uncaught exception 'NSGenericException', reason: 'The window has been marked as needing another Layout Window pass, but it has already had more Layout Window passes than there are views in the window.
         <NSWindow: 0xb21e4d000> 0x20d8 (8408) {{0, -180}, {1512, 1077}} en'
         terminating due to uncaught exception of type NSException
         */

        /// Grab the current toolbar, then remove it from the window.
        toolbarToRestoreAfterFullScreenTransition = toolbar
        toolbar = nil

        /// Trigger full screen toggle.
        super.toggleFullScreen(sender)

        /// When window finishes entering or exiting full screen, set its toolbar back to the previous value.
        guard cancellables.isEmpty else { return }

        NotificationCenter.default
            .publisher(for: NSWindow.didEnterFullScreenNotification, object: self)
            .sink { [weak self] _ in
                self?.restoreToolbarAfterFullScreenTransitionIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSWindow.didExitFullScreenNotification, object: self)
            .sink { [weak self] _ in
                self?.restoreToolbarAfterFullScreenTransitionIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func restoreToolbarAfterFullScreenTransitionIfNeeded() {
        guard #available(macOS 26, *) else { return }

        UILog(#function)

        toolbar = toolbarToRestoreAfterFullScreenTransition
    }
}
