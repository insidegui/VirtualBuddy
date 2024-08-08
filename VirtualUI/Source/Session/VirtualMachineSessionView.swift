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
    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager
    @EnvironmentObject private var controller: VMController
    @EnvironmentObject private var ui: VirtualMachineSessionUI

    @Environment(\.cocoaWindow)
    private var window

    /// ``VirtualMachineSessionView`` should only be initialized by ``VirtualMachineSessionUIManager``.
    internal init() { }

    private var vbWindow: VBRestorableWindow? {
        guard !ProcessInfo.isSwiftUIPreview else { return nil }
        
        guard let window = window as? VBRestorableWindow else {
            assertionFailure("VM window must be a VBRestorableWindow")
            return nil
        }
        return window
    }

    public var body: some View {
        ZStack {
            controllerStateView
        }
            .toolbar {
                if #available(macOS 14.0, *) {
                    VirtualMachineControls<VMController>()
                        .environmentObject(controller)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
            .background(backgroundView)
            .environmentObject(controller)
            .windowTitle(controller.virtualMachineModel.name)
            .windowStyleMask([.titled, .miniaturizable, .closable, .resizable])
            .confirmBeforeClosingWindow(callback: confirmBeforeClosing)
            .onWindowKeyChange { [weak sessionManager, weak ui] isKey in
                guard let sessionManager, let ui else { return }
                sessionManager.focusedSessionChanged.send(isKey ? .init(ui) : nil)
            }
            .onAppearOnce {
                guard vbWindow?.hasSavedFrame == false else { return }
                guard let display = controller.virtualMachineModel.configuration.hardware.displayDevices.first else { return }
                vbWindow?.resize(to: .fitScreen, for: display)
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
            .onReceive(screenshotTaken) { data in
                controller.storeScreenshot(with: data)
            }
            .onReceive(ui.makeWindowKey) {
                window?.makeKeyAndOrderFront(nil)
            }
            .task {
                if controller.options.autoBoot {
                    Task { try? await controller.start() }
                }
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
        case .paused(let vm), .savingState(let vm), .restoringState(let vm, _), .stateSaveCompleted(let vm, _):
            pausedView(with: vm)
        }
    }

    private let screenshotTaken = VMScreenshotter.Subject()

    @ViewBuilder
    private func vmView(with vm: VZVirtualMachine) -> some View {
        SwiftUIVMView(
            controllerState: .constant(.running(vm)),
            captureSystemKeys: controller.virtualMachineModel.configuration.captureSystemKeys,
            automaticallyReconfiguresDisplay: .constant(controller.virtualMachineModel.configuration.hardware.displayDevices.count > 0 ? controller.virtualMachineModel.configuration.hardware.displayDevices[0].automaticallyReconfiguresDisplay : false),
            screenshotSubject: screenshotTaken
        )
    }
    
    @ViewBuilder
    private func pausedView(with vm: VZVirtualMachine) -> some View {
        ZStack {
            vmView(with: vm)

            if case .restoringState(_, let package) = controller.state, let screenshot = package.screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            Rectangle()
                .foregroundStyle(Material.regular)

            ZStack {
                switch controller.state {
                case .paused:
                    circularStartButton
                case .savingState, .stateSaveCompleted:
                    VMProgressOverlay(
                        message: controller.state.isStateSaveCompleted ? "State Saved!" : "Saving Virtual Machine State",
                        duration: controller.state.isStateSaveCompleted ? 0 : 14
                    )
                case .restoringState:
                    VMProgressOverlay(message: "Restoring Virtual Machine State", duration: 14)
                default:
                    EmptyView()
                }
            }
            .animation(.bouncy, value: controller.state)
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
                .environment(\.backgroundMaterial, Material.thin)
                .environmentObject(controller)
                .frame(maxWidth: 400)
        }
    }
    
    @ViewBuilder
    private var circularStartButton: some View {
        Button {
            if controller.canStart {
                Task { try? await controller.start() }
            } else if controller.canResume {
                Task {
                    try? await controller.resume()
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
            VMScreenshotBackgroundView(vm: $controller.virtualMachineModel, options: $controller.options)
        }
    }

    private var confirmBeforeClosing: () async -> Bool {
        { [weak controller] in
            guard let controller else { return true }

            if controller.isIdle || controller.isStopped { return true }

            let confirmed = await NSAlert.runConfirmationAlert(
                title: "Stop Virtual Machine?",
                message: "If you close the window now, the virtual machine will be stopped.",
                continueButtonTitle: "Stop VM",
                cancelButtonTitle: "Cancel"
            )

            guard confirmed else { return false }

            try? await controller.forceStop()

            return true
        }
    }

}

struct VMScreenshotBackgroundView: View {
    
    @Binding var vm: VBVirtualMachine
    @Binding var options: VMSessionOptions

    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            
            MaterialView()
                .materialType(.popover)
                .materialBlendingMode(.withinWindow)
                .materialState(.followsWindowActiveState)
        }
        .onAppearOnce { updateImage(options: options) }
        .onReceive(vm.didInvalidateThumbnail) { updateImage(options: options) }
        .onChange(of: options) { newOptions in
            updateImage(options: newOptions)
        }
    }
    
    private func updateImage(options: VMSessionOptions) {
        if let restorePackage = options.stateRestorationPackage,
           let screenshot = restorePackage.screenshot
        {
            image = Image(nsImage: screenshot)
        } else if let screenshot = vm.screenshot {
            image = Image(nsImage: screenshot)
        } else {
            image = nil
        }
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
    var isIdle: Bool {
        return state == .idle
    }
    var isStarting: Bool {
        guard case .starting = state else { return false }
        return true
    }
    var isRunning: Bool {
        guard case .running = state else { return false }
        return true
    }
    var isStopped: Bool {
        guard case .stopped = state else { return false }
        return true
    }
}

#if DEBUG
#Preview {
    VirtualMachineSessionView()
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .environmentObject(VMLibraryController.preview)
        .environmentObject(VMController.preview)
        .environmentObject(VirtualMachineSessionUI.preview)
        .environmentObject(VirtualMachineSessionUIManager.shared)

}
#endif
