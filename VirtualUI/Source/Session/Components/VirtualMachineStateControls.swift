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

    @State private var actionTask: Task<Void, Never>?
    @State private var isPopoverPresented = false
    @State private var textFieldContent = ""
    
    var body: some View {
        Group {
            switch controller.state {
            case .idle, .paused, .stopped, .savingState, .restoringState, .stateSaveCompleted, .resizingDisk:
                Button {
                    runToolbarAction {
                        if controller.state.canResume {
                            try await controller.resume()
                        } else {
                            try await controller.start()
                        }
                    }
                } label: {
                    Image(systemName: "play")
                }
                .disabled(controller.state.isSavingState || controller.state.isRestoringState || controller.state.isResizingDisk)
            case .starting, .running:
                if controller.virtualMachineModel.supportsStateRestoration {
                    Button {
                        /**
                         Ability to save new states has been temporarily disabled in version 2 due to issues with its implementation.
                         This prevents users from creating bad state saves before the correct implementation is shipped.
                         */
                        guard UserDefaults.standard.bool(forKey: "VBForceEnableSaveStateFeature") else {
                            NSAlert(error: "Sorry, this feature has been temporarily disabled. It will be back in a future update.").runModal()
                            return
                        }
                        
                        runToolbarAction {
                            textFieldContent = "Save-" + DateFormatter.savedStateFileName.string(from: .now)
                            isPopoverPresented = true
                        }
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .help("Save current state")
                    .popover(isPresented: $isPopoverPresented) {
                        VStack {
                            Text("Save current state")
                                .font(.headline)
                            TextField("Name current state", text: $textFieldContent)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.top, 15)
                                .padding(.bottom, 15)

                            HStack {
                                Spacer()

                                Button("Cancel") {
                                    isPopoverPresented = false
                                }
                                .padding(.trailing, 8)
                                .keyboardShortcut(.cancelAction)

                                Button("Save") {
                                    isPopoverPresented = false

                                    runToolbarAction {
                                        try await saveState()
                                    }
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .frame(width: 300)
                        .padding()
                    }

                    Button {
                        runToolbarAction {
                            try await controller.pause()
                        }
                    } label: {
                        Image(systemName: "pause")
                    }
                    .help("Pause")

                    Button {
                        runToolbarAction {
                            try await controller.stop()
                        }
                    } label: {
                        Image(systemName: "power")
                    }
                    .help("Shut down")
                }
            }
        }
        .symbolVariant(.fill)
        .disabled(actionTask != nil)
    }

    private func runToolbarAction(alertForErrors: Bool = false, action: @escaping @MainActor () async throws -> Void) {
        actionTask = Task { @MainActor in
            defer { actionTask = nil }

            do {
                try await action()
            } catch {
                guard alertForErrors else { return }

                NSAlert(error: error).runModal()
            }
        }
    }

    @MainActor
    private func saveState() async throws {
        do {
            try await controller.saveState(snapshotName: textFieldContent)
        } catch {
            guard !(error is CancellationError) else { return }
            throw error
        }
    }
}

private extension DateFormatter {
    static let savedStateFileName: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd_HH;mm;ss"
        return f
    }()
}
