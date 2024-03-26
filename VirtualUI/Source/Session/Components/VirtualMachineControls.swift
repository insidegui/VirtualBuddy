//
//  VirtualMachineControls.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 24/10/23.
//

import SwiftUI
import VirtualCore

protocol VirtualMachineStateController: ObservableObject {
    var state: VMState { get }
    
    func start() async throws
    func stop() async throws
    func pause() async throws
    func resume() async throws
    
    @available(macOS 14.0, *)
    func saveState() async throws
}

extension VMController: VirtualMachineStateController { }

@available(macOS 14.0, *)
struct VirtualMachineControls<Controller: VirtualMachineStateController>: View {
    @EnvironmentObject private var controller: Controller

    @State private var actionTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch controller.state {
            case .idle, .paused, .stopped, .savingState, .restoringState, .stateSaveCompleted:
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
                .disabled(controller.state.isSavingState || controller.state.isRestoringState)
            case .starting, .running:
                Button {
                    runToolbarAction {
                        try await controller.pause()
                    }
                } label: {
                    Image(systemName: "pause")
                }

                Button {
                    runToolbarAction {
                        try await controller.stop()
                    }
                } label: {
                    Image(systemName: "power")
                }

                if #available(macOS 14.0, *) {
                    Button {
                        runToolbarAction {
                            try await controller.saveState()
                        }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .help("Save current state")
                }
            }
        }
        .symbolVariant(.fill)
        .disabled(actionTask != nil)
    }

    private func runToolbarAction(alertForErrors: Bool = false, action: @escaping () async throws -> Void) {
        actionTask = Task {
            defer { actionTask = nil }

            do {
                try await action()
            } catch {
                guard alertForErrors else { return }

                NSAlert(error: error).runModal()
            }
        }
    }
}

#if DEBUG
private final class PreviewVirtualMachineStateController: VirtualMachineStateController {
    @MainActor
    @Published var state: VMState = .idle

    @MainActor
    func start() async throws {
        state = .starting

        try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

        state = .running(.preview)
    }

    @MainActor
    func stop() async throws {
        try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)

        state = .stopped(nil)
    }

    @MainActor
    func pause() async throws {
        state = .paused(.preview)
    }

    @MainActor
    func resume() async throws {
        state = .running(.preview)
    }

    @available(macOS 14.0, *)
    @MainActor
    func saveState() async throws {
        state = .paused(.preview)
    }

}

@available(macOS 14.0, *)
private struct _VirtualMachineControlsPreview: View {
    var body: some View {
        Text("Preview")
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    VirtualMachineControls<PreviewVirtualMachineStateController>()
                        .environmentObject(PreviewVirtualMachineStateController())
                }
            }
    }
}

@available(macOS 14.0, *)
#Preview {
    _VirtualMachineControlsPreview()
}
#endif
