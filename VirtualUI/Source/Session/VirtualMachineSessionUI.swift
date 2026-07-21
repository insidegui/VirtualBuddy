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
                    .id(ObjectIdentifier(controller))
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

@MainActor
private final class WeakVMControllerObserver: ObservableObject {
    private(set) weak var controller: VMController?

    private var cancellable: AnyCancellable?

    init(controller: VMController) {
        self.controller = controller
        self.cancellable = controller.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }
}

private struct VirtualMachineGuestActions: View {
    /// Commands are installed in the app-wide main menu and may outlive the session window.
    /// This observer forwards updates without retaining the VM controller.
    @StateObject private var observer: WeakVMControllerObserver

    @State private var actionTask: Task<Void, Never>?

    private var controller: VMController? { observer.controller }

    init(controller: VMController) {
        _observer = StateObject(wrappedValue: WeakVMControllerObserver(controller: controller))
    }

    var body: some View {
        Group {
            if controller?.state.isRunning == true {
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
                Button { [observer] in
                    runGuestAction {
                        guard let controller = observer.controller else { return }

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
                .disabled(actionTask != nil || !((controller?.canStart == true) || (controller?.canResume == true)))
            }

            Button { [observer] in
                runGuestAction {
                    guard let controller = observer.controller else { return }
                    try await controller.pause()
                }
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(actionTask != nil || controller?.canPause != true)

            Divider()

            VirtualMachineNetworkCommands(observer: observer)
        }
    }

    private var stopButton: some View {
        Button { [observer] in
            runGuestAction {
                guard let controller = observer.controller else { return }
                try await controller.stop()
            }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(actionTask != nil)
    }

    private var forceStopButton: some View {
        Button { [observer] in
            runGuestAction {
                guard let controller = observer.controller else { return }
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
    @ObservedObject var observer: WeakVMControllerObserver

    private var controller: VMController? { observer.controller }

    var body: some View {
        Menu {
            Button { [observer] in
                performNetworkAction {
                    guard let controller = observer.controller else { return }
                    try controller.reconnectNetwork()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .disabled(controller?.canReconnectNetwork != true)

            Divider()

            let availableInterfaces = controller?.availableBridgeInterfaces ?? []

            if availableInterfaces.isEmpty {
                Button {
                } label: {
                    Label("No Host Interfaces Available", systemImage: "network.slash")
                }
                .disabled(true)
            } else {
                ForEach(availableInterfaces) { interface in
                    Button { [observer] in
                        performNetworkAction {
                            guard let controller = observer.controller else { return }
                            try controller.changeBridgeInterface(to: interface.id)
                        }
                    } label: {
                        Label(
                            interfaceDisplayName(interface),
                            systemImage: isActive(interface) ? "checkmark" : "network"
                        )
                    }
                    .disabled(controller?.canChangeBridgeInterface != true || isActive(interface))
                }
            }
        } label: {
            Label("Network", systemImage: "network")
        }
    }

    private func isActive(_ interface: VBNetworkDeviceInterface) -> Bool {
        controller?.activeBridgeInterfaceIdentifiers == [interface.id]
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
