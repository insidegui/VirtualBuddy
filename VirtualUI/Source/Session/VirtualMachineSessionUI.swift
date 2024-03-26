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

    public let virtualMachine: VBVirtualMachine

    private lazy var cancellables = Set<AnyCancellable>()

    public init(with virtualMachine: VBVirtualMachine) {
        self.virtualMachine = virtualMachine

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

}

public struct VirtualMachineWindowCommands: View {
    @EnvironmentObject private var manager: VirtualMachineSessionUIManager

    @State private var focusedSession: VirtualMachineSessionUI?

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
        .onReceive(manager.focusedSessionChanged) {
            focusedSession = $0
            focusedSession?.lockProportions = lockProportions
        }
        .onChange(of: lockProportions) { [lockProportions] newValue in
            guard newValue != lockProportions else { return }
            focusedSession?.lockProportions = newValue
        }

        Divider()
    }

}
