import SwiftUI
import VirtualCore
import OSLog

@MainActor
public extension VirtualMachineSessionUIManager {

    /// Whether quitting needs to stop any virtual machines first.
    var hasActiveVirtualMachines: Bool {
        sessions.values.contains { $0.needsStoppingBeforeClose }
    }

    /// Saves (or shuts down) every active virtual machine so that the app can quit.
    ///
    /// The app keeps running if anything fails or the user cancels. Requests that arrive while this is in progress join it.
    /// - Returns: `true` if the app may quit.
    func prepareForTermination() async -> Bool {
        let participants = sessions.values
            .sorted { $0.virtualMachine.name.localizedStandardCompare($1.virtualMachine.name) == .orderedAscending }
            .map { SessionTerminationParticipant(name: $0.virtualMachine.name, controller: $0.controller, closer: $0.closer) }

        return await terminationCoordinator.prepareForTermination(participants: participants)
    }

    /// Asks the termination in progress to stop.
    func cancelTermination() {
        terminationCoordinator.cancel()
    }
}

// MARK: - Presentation

/// Reports the progress of quitting in one place, whatever the number of virtual machines, and asks the questions quitting needs to ask.
@MainActor
final class TerminationPresenter: SessionTerminationPresenting {
    private var panel: TerminationProgressPanel?

    weak var manager: VirtualMachineSessionUIManager?

    func showProgress(for participants: [SessionTerminationParticipant]) {
        guard let manager else { return }

        let sessions = manager.sessionsInProgress(for: participants)

        let panel = TerminationProgressPanel(sessions: sessions) { [weak manager] in
            manager?.cancelTermination()
        }
        panel.show()

        self.panel = panel
    }

    func dismissProgress() {
        panel?.close()
        panel = nil
    }

    func confirmShutDown(of machines: [(name: String, reason: String)]) async -> Bool {
        await SavedSessionPrompts.confirmShutDownInsteadOfSaving(names: machines, from: nil)
    }
}

@MainActor
extension VirtualMachineSessionUIManager {
    func sessionsInProgress(for participants: [SessionTerminationParticipant]) -> [VirtualMachineSessionUI] {
        sessions.values.filter { session in participants.contains { $0.controller === session.controller } }
            .sorted { $0.virtualMachine.name.localizedStandardCompare($1.virtualMachine.name) == .orderedAscending }
    }

    /// Holds the app open while virtual machines are being stopped. Releasing doesn't let the app quit on its own:
    /// quitting only ever happens as the answer to the app delegate's termination request.
    static func holdTermination() -> @MainActor () -> Void {
        NSApp.shouldTerminateWhenLastAssertionInvalidated = false
        let assertion = NSApp.preventTermination(reason: "saving virtual machines")

        return {
            NSApp.shouldTerminateWhenLastAssertionInvalidated = false
            assertion.invalidate()
        }
    }
}

// MARK: - Progress

@MainActor
private final class TerminationProgressPanel {
    private let panel: NSPanel

    init(sessions: [VirtualMachineSessionUI], onCancel: @escaping () -> Void) {
        let view = TerminationProgressView(sessions: sessions, onCancel: onCancel)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quitting VirtualBuddy"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: view)
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.contentViewController = nil
        panel.close()
    }
}

private struct TerminationProgressView: View {
    var sessions: [VirtualMachineSessionUI]
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sessions, id: \.virtualMachine.id) { session in
                    TerminationProgressRow(ui: session, controller: session.controller)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct TerminationProgressRow: View {
    @ObservedObject var ui: VirtualMachineSessionUI
    @ObservedObject var controller: VMController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ui.virtualMachine.name)
                    .font(.headline)
                Spacer()
                Text(status)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if case .saving(_, let phase) = controller.state {
                ProgressView(value: phase.fractionCompleted)
            } else if isWorking {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    private var isWorking: Bool {
        controller.state.isActive || ui.activity != nil
    }

    private var status: String {
        switch controller.state {
        case .saving(_, let phase): "\(phase.title)…"
        case .saved: "Saved"
        case .idle, .stopped: "Shut down"
        case .starting, .resizingDisk, .restoring: "Waiting"
        case .running, .paused: ui.activity == .shuttingDown ? "Shutting down…" : "Waiting"
        case .recoveryRequired: "Needs attention"
        }
    }
}
