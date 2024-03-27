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
    public convenience init(with virtualMachine: VBVirtualMachine, options: VMSessionOptions?) {
        self.init(controller: VMController(with: virtualMachine, options: options))
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
        .onChange(of: lockProportions) { [lockProportions] newValue in
            guard newValue != lockProportions else { return }
            focusedSession?.lockProportions = newValue
        }

        Divider()
    }

}
