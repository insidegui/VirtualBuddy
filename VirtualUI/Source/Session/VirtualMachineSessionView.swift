//
//  VirtualMachineSessionView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore
import Combine

public struct VirtualMachineSessionView: View {
    @StateObject var controller: VMController
    @StateObject var ui: VirtualMachineSessionUI
    
    @EnvironmentObject var library: VMLibraryController
    @EnvironmentObject var sessionManager: VirtualMachineSessionUIManager

    @Environment(\.cocoaWindow)
    private var window

    private var vbWindow: VBRestorableWindow? {
        guard let window = window as? VBRestorableWindow else {
            assertionFailure("VM window must be a VBRestorableWindow")
            return nil
        }
        return window
    }

    public var body: some View {
        controllerStateView
            .edgesIgnoringSafeArea(.all)
            .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
            .background(backgroundView)
            .environmentObject(controller)
            .windowTitle(controller.virtualMachineModel.name)
            .windowStyleMask([.titled, .miniaturizable, .closable, .resizable])
            .confirmBeforeClosingWindow(callback: confirmBeforeClosing)
            .onWindowKeyChange { isKey in
                sessionManager.focusedSessionChanged.send(isKey ? ui : nil)
            }
            .onReceive(ui.resizeWindow) { size in
                guard let display = controller.virtualMachineModel.configuration.hardware.displayDevices.first else {
                    assertionFailure("VM doesn't have a display")
                    return
                }

                vbWindow?.resize(to: size, for: display)
            }
            .onReceive(ui.setWindowAspectRatio) { ratio in
                vbWindow?.applyAspectRatio(ratio)
            }
    }
    
    @ViewBuilder
    private var controllerStateView: some View {
        switch controller.state {
        case .idle:
            startableStateView(with: nil)
        case .stopped(let error):
            startableStateView(with: error)
        case .starting:
            ProgressView()
        case .running(let vm):
            vmView(with: vm)
        case .paused(let vm):
            pausedView(with: vm)
        }
    }
    
    @ViewBuilder
    private func vmView(with vm: VZVirtualMachine) -> some View {
        SwiftUIVMView(
            controllerState: .constant(.running(vm)),
            captureSystemKeys: controller.virtualMachineModel.configuration.captureSystemKeys
        )
    }
    
    @ViewBuilder
    private func pausedView(with vm: VZVirtualMachine) -> some View {
        ZStack {
            vmView(with: vm)
            
            Rectangle()
                .foregroundStyle(Material.regular)
            
            circularStartButton
        }
    }
    
    private func startableStateView(with error: Error?) -> some View {
        VStack(spacing: 28) {
            if let error = error {
                Text("The machine has stopped due to an error: \(String(describing: error))")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .font(.caption)
            }
            
            circularStartButton
            
            VMSessionConfigurationView()
                .environmentObject(controller)
        }
    }
    
    @ViewBuilder
    private var circularStartButton: some View {
        Button {
            if controller.canStart {
                Task { await controller.startVM() }
            } else if controller.canResume {
                Task {
                    try await controller.resume()
                }
            }
        } label: {
            Image(systemName: "play")
        }
        .buttonStyle(VMCircularButtonStyle())
    }

    @ViewBuilder
    private var backgroundView: some View {
        if controller.isRunning {
            Color.black
        } else {
            VMScreenshotBackgroundView(vm: $controller.virtualMachineModel)
        }
    }

    private func confirmBeforeClosing() async -> Bool {
        guard controller.isStarting || controller.isRunning else { return true }

        let confirmed = await NSAlert.runConfirmationAlert(
            title: "Stop Virtual Machine?",
            message: "If you close the window now, the virtual machine will be stopped.",
            continueButtonTitle: "Stop VM",
            cancelButtonTitle: "Cancel"
        )

        guard confirmed else { return false }

        try? await controller.forceStop()

        /// Workaround for cursor disappearing due to it being captured
        /// between the alert confirmation and the VM stopping.
        try? await Task.sleep(nanoseconds: 100_000_000)
        NSCursor.unhide()

        return true
    }

}

struct VMScreenshotBackgroundView: View {
    
    @Binding var vm: VBVirtualMachine
    
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            MaterialView()
                .materialType(.popover)
                .materialBlendingMode(.withinWindow)
                .materialState(.followsWindowActiveState)
        }
        .onAppearOnce { updateImage() }
        .onReceive(vm.didInvalidateThumbnail) { updateImage() }
    }
    
    private func updateImage() {
        guard let screenshot = vm.screenshot else { return }
        image = Image(nsImage: screenshot)
    }
    
}

struct VMCircularButtonStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        mainContent(with: configuration)
            .contentShape(Circle())
    }
    
    private func mainContent(with configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 50, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(30)
            .background(Circle().fill(Material.thin))
            .brightness(configuration.isPressed ? 0.3 : 0)
            .symbolVariant(.fill)
    }
    
}

extension VMController {
    var isRunning: Bool {
        guard case .running = state else { return false }
        return true
    }
    var isStarting: Bool {
        guard case .starting = state else { return false }
        return true
    }
}
