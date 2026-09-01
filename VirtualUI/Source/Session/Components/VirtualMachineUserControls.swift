import SwiftUI
import VirtualCore

struct VirtualMachineUserControls: View {
    @EnvironmentObject private var ui: VirtualMachineSessionUI

    var body: some View {
        Group {
            Toggle(isOn: $ui.captureKeyboardEvents) {
                Label("Capture keyboard", systemImage: ui.virtualMachine.keyboardDeviceSFSymbol)
                    .labelStyle(.iconOnly)
            }
            .help(ui.captureKeyboardEvents ? "Click to disconnect keyboard from virtual machine" : "Click to connect keyboard to virtual machine")

            Toggle(isOn: $ui.captureMouseEvents) {
                Label("Capture mouse", systemImage: ui.virtualMachine.pointingDeviceSFSymbol)
                    .labelStyle(.iconOnly)
            }
            .help(ui.captureMouseEvents ? "Click to disconnect \(ui.virtualMachine.pointingDeviceName) from virtual machine" : "Click to connect \(ui.virtualMachine.pointingDeviceName) to virtual machine")
        }
    }
}

// MARK: - Helpers

extension VBVirtualMachine {
    var pointingDeviceName: String { configuration.pointingDeviceName }
    var pointingDeviceSFSymbol: String { configuration.pointingDeviceSFSymbol }
    var keyboardDeviceSFSymbol: String { configuration.keyboardDeviceSFSymbol }
}

extension VBMacConfiguration {
    var pointingDeviceName: String { hardware.pointingDevice.kind.name.lowercased() }

    var pointingDeviceSFSymbol: String {
        switch systemType {
        case .mac:
            switch hardware.pointingDevice.kind {
            case .mouse: "magicmouse"
            case .trackpad: "rectangle.and.hand.point.up.left.filled"
            }
        case .linux:
            switch hardware.pointingDevice.kind {
            case .mouse: "computermouse"
            case .trackpad: "rectangle.and.hand.point.up.left.filled"
            }
        }
    }

    var keyboardDeviceSFSymbol: String { "keyboard" }
}
