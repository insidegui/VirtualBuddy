//
//  VirtualMachineStateControls.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 24/10/23.
//

import SwiftUI
import VirtualCore

struct VirtualMachineStateControls: View {
    @EnvironmentObject private var controller: VMController
    @EnvironmentObject private var ui: VirtualMachineSessionUI

    @State private var actionTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch controller.state {
            case .idle, .stopped, .saved:
                Button {
                    runToolbarAction { await ui.startOrResume() }
                } label: {
                    Image(systemName: "play")
                }
                .help(controller.state.isSaved ? "Resume" : "Start")

            case .starting, .resizingDisk, .saving, .restoring:
                Button { } label: {
                    Image(systemName: "play")
                }
                .disabled(true)

            case .recoveryRequired:
                Button {
                    runToolbarAction { await ui.reviewRecoveryOptions() }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .help("Review recovery options")

            case .paused:
                Button {
                    runToolbarAction { try? await controller.resume() }
                } label: {
                    Image(systemName: "play")
                }
                .help("Resume")

                saveAndCloseButton

            case .running:
                saveAndCloseButton

                Button {
                    runToolbarAction { try? await controller.pause() }
                } label: {
                    Image(systemName: "pause")
                }
                .help("Pause")

                Button {
                    runToolbarAction { try? await controller.stop() }
                } label: {
                    Image(systemName: "power")
                }
                .help("Shut down")
            }
        }
        .symbolVariant(.fill)
        .disabled(actionTask != nil)
    }

    private var saveAndCloseButton: some View {
        Button {
            runToolbarAction { await ui.saveAndClose() }
        } label: {
            Image(systemName: "tray.and.arrow.down")
        }
        .help(saveAndCloseHelp)
    }

    private var saveAndCloseHelp: String {
        if let issue = controller.saveEligibility.primaryIssue {
            "Save & Close isn’t available. \(issue.explanation)"
        } else {
            "Save & Close"
        }
    }

    private func runToolbarAction(action: @escaping @MainActor () async -> Void) {
        actionTask = Task { @MainActor in
            defer { actionTask = nil }

            await action()
        }
    }
}
