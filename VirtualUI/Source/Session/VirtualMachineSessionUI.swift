import SwiftUI
import VirtualCore
import Combine
import AVFoundation

public final class VirtualMachineSessionUI: ObservableObject {

    public enum WindowSize: Int {
        case pointAccurate
        case pixelAccurate
        case fitScreen
    }

    @Published public var lockProportions = false

    let setWindowAspectRatio = PassthroughSubject<CGSize?, Never>()
    let resizeWindow = PassthroughSubject<WindowSize, Never>()
    let makeWindowKey = PassthroughSubject<Void, Never>()

    public let controller: VMController
    public let virtualMachine: VBVirtualMachine

    private lazy var cancellables = Set<AnyCancellable>()

    @MainActor
    public convenience init(with virtualMachine: VBVirtualMachine, library: VMLibraryController, options: VMSessionOptions?) {
        self.init(controller: VMController(with: virtualMachine, library: library, options: options))
    }

    @MainActor
    public init(controller: VMController) {
        self.controller = controller
        self.virtualMachine = controller.virtualMachineModel

        $lockProportions.dropFirst().removeDuplicates().sink { [weak self] newValue in
            guard let self = self else { return }

            guard let display = self.virtualMachine.configuration.hardware.displayDevices.first else {
                assertionFailure("VM doesn't have a display")
                return
            }

            let ratio = newValue ? CGSize(width: display.width, height: display.height) : nil

            self.setWindowAspectRatio.send(ratio)
        }
        .store(in: &cancellables)
    }

    @MainActor
    public func update(with newOptions: VMSessionOptions?) {
        guard let newOptions else { return }

        if newOptions != controller.options {
            /// If we're trying to launch a virtual machine with custom options and those don't match the current options,
            /// we must ensure that the VM is not currently running/paused, otherwise changing the options won't have any effect.
            /// If the VM is currently not in a state where options can be changed, then the user will be prompted to shut it down before doing so.
            guard controller.canStart else {
                let alert = NSAlert()
                alert.messageText = "Virtual Machine Already in Use"
                alert.informativeText = "\"\(virtualMachine.name)\" is already in use. Please shut down the virtual machine before starting it with the new options."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
        }

        /// The VM is currently in a state where it's safe to change the options, just update the options for the controller.
        controller.options = newOptions
    }

    @MainActor
    public func bringToFront() {
        makeWindowKey.send()
    }

    deinit {
        VBMemoryLeakDebugAssertions.vb_objectIsBeingReleased(self)
    }
}

public struct VirtualMachineWindowCommands: View {
    @EnvironmentObject private var manager: VirtualMachineSessionUIManager

    @State private var focusedSessionReference: WeakReference<VirtualMachineSessionUI>?
    private var focusedSession: VirtualMachineSessionUI? { focusedSessionReference?.object }

    @AppStorage("vm.window.proportions.locked")
    private var lockProportions = false

    public init() { }

    public var body: some View {
        Group {
            Toggle("Lock Proportions", isOn: $lockProportions)

            Button("Point Accurate") {
                focusedSession?.resizeWindow.send(.pointAccurate)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Pixel Accurate") {
                focusedSession?.resizeWindow.send(.pixelAccurate)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Fit Screen") {
                focusedSession?.resizeWindow.send(.fitScreen)
            }
            .keyboardShortcut("3", modifiers: .command)
        }
        .disabled(focusedSession == nil)
        .onReceive(manager.focusedSessionChanged) { ref in
            focusedSessionReference = ref
            ref?.object?.lockProportions = lockProportions
        }
        .onChange(of: lockProportions) { _, newValue in
            focusedSession?.lockProportions = newValue
        }

        Divider()
    }

}

public struct VirtualMachineGuestCommands: View {
    @EnvironmentObject private var manager: VirtualMachineSessionUIManager

    @State private var focusedSessionReference: WeakReference<VirtualMachineSessionUI>?
    private var focusedSession: VirtualMachineSessionUI? { focusedSessionReference?.object }

    public init() { }

    public var body: some View {
        Group {
            if let controller = focusedSession?.controller {
                VirtualMachineGuestActions(controller: controller)
            } else {
                /// Dummy item for when session is not available.
                Button {
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }
        }
        .disabled(focusedSession == nil)
        .onReceive(manager.focusedSessionChanged) { ref in
            focusedSessionReference = ref
        }
    }
}

private struct VirtualMachineGuestActions: View {
    @ObservedObject var controller: VMController

    @State private var actionTask: Task<Void, Never>?

    var body: some View {
        Group {
            if controller.state.isRunning {
                stopButton
                    .modifier { button in
                        if #available(macOS 15.0, *) {
                            button.modifierKeyAlternate(.option) {
                                forceStopButton
                            }
                        } else {
                            button
                        }
                    }
            } else {
                Button {
                    runGuestAction {
                        if controller.canResume {
                            try await controller.resume()
                        } else {
                            try await controller.start()
                        }
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actionTask != nil || !(controller.canStart || controller.canResume))
            }

            Button {
                runGuestAction {
                    try await controller.pause()
                }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(actionTask != nil || !controller.canPause)

            Divider()

            VirtualMachineNetworkCommands(controller: controller)
        }
    }

    private var stopButton: some View {
        Button {
            runGuestAction {
                try await controller.stop()
            }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(actionTask != nil)
    }

    private var forceStopButton: some View {
        Button {
            runGuestAction {
                try await controller.forceStop()
            }
        } label: {
            Label("Force Stop", systemImage: "stop.circle.fill")
        }
        .disabled(actionTask != nil)
    }

    private func runGuestAction(_ action: @escaping @MainActor () async throws -> Void) {
        actionTask = Task { @MainActor in
            defer { actionTask = nil }

            do {
                try await action()
            } catch {
                NSApp.presentError(error)
            }
        }
    }
}

private struct VirtualMachineNetworkCommands: View {
    @ObservedObject var controller: VMController

    var body: some View {
        Menu {
            Button {
                performNetworkAction {
                    try controller.reconnectNetwork()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .disabled(!controller.canReconnectNetwork)

            Divider()

            let availableInterfaces = controller.availableBridgeInterfaces

            if availableInterfaces.isEmpty {
                Button {
                } label: {
                    Label("No Host Interfaces Available", systemImage: "network.slash")
                }
                .disabled(true)
            } else {
                ForEach(availableInterfaces) { interface in
                    Button {
                        performNetworkAction {
                            try controller.changeBridgeInterface(to: interface.id)
                        }
                    } label: {
                        Label(
                            interfaceDisplayName(interface),
                            systemImage: isActive(interface) ? "checkmark" : "network"
                        )
                    }
                    .disabled(!controller.canChangeBridgeInterface || isActive(interface))
                }
            }
        } label: {
            Label("Network", systemImage: "network")
        }
    }

    private func isActive(_ interface: VBNetworkDeviceInterface) -> Bool {
        controller.activeBridgeInterfaceIdentifiers == [interface.id]
    }

    private func interfaceDisplayName(_ interface: VBNetworkDeviceInterface) -> String {
        guard interface.name != interface.id else { return interface.name }
        return "\(interface.name) (\(interface.id))"
    }

    private func performNetworkAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            NSApp.presentError(error)
        }
    }
}
