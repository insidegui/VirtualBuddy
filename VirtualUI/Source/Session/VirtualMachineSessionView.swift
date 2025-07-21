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
            .onReceive(ui.makeWindowKey) {
                window?.makeKeyAndOrderFront(nil)
            }
            .task {
                if controller.options.autoBoot {
                    Task { try? await controller.start() }
                }
            }
            .toolbar {
                if #available(macOS 14.0, *) {
                    VirtualMachineControls<VMController>()
                        .environmentObject(controller)
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
        case .starting(let message):
            VStack(spacing: 12) {
                ProgressView()

                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }
        case .running(let vm):
            vmView(with: vm)
        case .paused(let vm), .savingState(let vm), .restoringState(let vm, _), .stateSaveCompleted(let vm, _):
            pausedView(with: vm)
        }
    }

    @ViewBuilder
    private func vmView(with vm: VZVirtualMachine) -> some View {
        SwiftUIVMView(
            controllerState: .constant(.running(vm)),
            captureSystemKeys: controller.virtualMachineModel.configuration.captureSystemKeys,
            isDFUModeVM: controller.options.bootInDFUMode,
            vmECID: controller.virtualMachineModel.ECID,
            automaticallyReconfiguresDisplay: .constant(controller.virtualMachineModel.configuration.hardware.displayDevices.count > 0 ? controller.virtualMachineModel.configuration.hardware.displayDevices[0].automaticallyReconfiguresDisplay : false)
        )
    }
    
    @ViewBuilder
    private func pausedView(with vm: VZVirtualMachine) -> some View {
        ZStack {
            vmView(with: vm)

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
            
            // Add hover overlay for screenshot functionality
            VMSnapshotHoverOverlay()
                .environmentObject(controller)
        }
    }
    
    private func startableStateView(with error: Error?) -> some View {
        ZStack {
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
            
            // Add hover overlay for screenshot functionality when VM is stopped/idle
            VMSnapshotHoverOverlay()
                .environmentObject(controller)
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
        VirtualMachineSessionBackgroundView(
            content: controller.virtualMachineModel.blurHashBackgroundContent,
            isRunning: controller.isRunning
        )
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

struct VirtualMachineSessionBackgroundView: View {
    var content: BlurHashFullBleedBackground.Content
    var isRunning: Bool

    var body: some View {
        ZStack {
            Color.black

            if !isRunning {
                switch content {
                case .blurHash(let token):
                    BlurHashFullBleedBackground(blurHash: token)
                        .fullBleedBackgroundBrightness(-0.2)
                case .customImage(let image):
                    BlurHashFullBleedBackground(image: image)
                        .fullBleedBackgroundBrightness(-0.1)
                        .fullBleedBackgroundSaturation(0.8)
                }

                Color.black.opacity(0.3)
            }
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

extension VBVirtualMachine {
    var blurHashBackgroundContent: BlurHashFullBleedBackground.Content {
        if let thumbnail {
            .customImage(thumbnail)
        } else {
            .blurHash(metadata.backgroundHash)
        }
    }
}

#if DEBUG
struct VirtualMachineSessionViewPreview: View {
    var body: some View {
        VirtualMachineSessionView()
            .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
            .environmentObject(VMLibraryController.preview)
            .environmentObject(VMController.preview)
            .environmentObject(VirtualMachineSessionUI.preview)
            .environmentObject(VirtualMachineSessionUIManager.shared)
    }
}

#Preview {
    VirtualMachineSessionViewPreview()
}
#endif
