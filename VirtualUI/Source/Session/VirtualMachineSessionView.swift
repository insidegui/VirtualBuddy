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
            if !controller.state.isRunning {
                backgroundView
            }

            controllerStateView

            if ui.activity == .shuttingDown {
                ShuttingDownOverlay()
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .environmentObject(controller)
        .windowTitle(controller.virtualMachineModel.name)
        .windowTitleBarTransparent(!controller.state.isRunning)
        .windowStyleMask([.titled, .miniaturizable, .closable, .resizable])
        .confirmBeforeClosingWindow(callback: confirmBeforeClosing)
        .task { ui.hostWindow = window }
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
        /// This takes care of booting when initially opening a session with a deep link that wants auto-boot.
        /// Booting after the session is already open is handled by ``VirtualMachineSessionUI``.
        .task {
            if controller.options.autoBoot {
                Task { await ui.startOrResume() }
            }
        }
        .toolbar {
            if controller.isRunning {
                if let guestAppStatus {
                    ToolbarItem(placement: .primaryAction) {
                        GuestAppStatusControl(status: guestAppStatus)
                    }

                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed)
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    VirtualMachineUserControls()
                }
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                VirtualMachineStateControls()
            }
        }
    }
    
    /// The guest app can't run when the virtual machine starts up in recovery, DFU, or from its install media.
    private var guestAppStatus: GuestAppConnectionStatus? {
        guard !controller.options.requestsSpecialBoot else { return nil }
        return controller.guestAppConnectionStatus
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
        case .resizingDisk(let message):
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
        case .paused(let vm):
            pausedView(with: vm) {
                circularStartButton
            }
        case .saving(let vm, let phase):
            pausedView(with: vm) {
                SavedSessionProgressOverlay(title: "Saving…", phase: phase)
            }
        case .restoring(let vm, let phase):
            if let vm {
                pausedView(with: vm) {
                    SavedSessionProgressOverlay(title: "Resuming…", phase: phase)
                }
            } else {
                SavedSessionProgressOverlay(title: "Resuming…", phase: phase)
            }
        case .saved(let descriptor):
            startableStateView(with: nil, savedSession: descriptor)
        case .recoveryRequired(let issue):
            recoveryRequiredView(issue: issue)
        }
    }

    @ViewBuilder
    private func vmView(with vm: VZVirtualMachine) -> some View {
        SwiftUIVMView(
            controllerState: .constant(.running(vm)),
            captureSystemKeysEnabled: controller.virtualMachineModel.configuration.captureSystemKeys,
            isDFUModeVM: controller.options.bootInDFUMode,
            vmECID: controller.virtualMachineModel.ECID,
            automaticallyReconfiguresDisplay: .constant(controller.virtualMachineModel.configuration.hardware.displayDevices.count > 0 ? controller.virtualMachineModel.configuration.hardware.displayDevices[0].automaticallyReconfiguresDisplay : false)
        )
        .virtualMachineEventDeliveryMask(ui.eventDeliveryMask)
    }
    
    @ViewBuilder
    private func pausedView<Overlay: View>(with vm: VZVirtualMachine, @ViewBuilder overlay: () -> Overlay) -> some View {
        ZStack {
            vmView(with: vm)

            Rectangle()
                .foregroundStyle(Material.regular)

            overlay()
        }
        .animation(.bouncy, value: controller.state)
    }
    
    private func startableStateView(with error: Error?, savedSession: VBSavedSessionDescriptor? = nil) -> some View {
        VStack(spacing: 28) {
            if let error = error {
                Text(startupErrorMessage(for: error))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .font(.caption)
            }

            if let savedSession {
                SavedSessionBadge(descriptor: savedSession)
            }
            
            circularStartButton
            
            VMSessionConfigurationView()
                .environment(\.backgroundMaterial, Material.thin)
                .environmentObject(controller)
                .environment(library.templatesController)
                .frame(maxWidth: 400)
        }
    }

    private func recoveryRequiredView(issue: SavedSessionIssue) -> some View {
        VStack(spacing: 20) {
            Label("Saved", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)

            Text(issue.explanation)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(maxWidth: 420)

            Button("Review Recovery Options…") {
                Task { await ui.reviewRecoveryOptions() }
            }
            .controlSize(.large)
        }
    }

    private func startupErrorMessage(for error: Error) -> String {
        if error.isMaximumActiveVirtualMachinesError {
            return """
            VirtualBuddy can't start this virtual machine because macOS has reached the system limit for active virtual machines. \
            This is a system limitation. Shut down another virtual machine before starting this one.
            """
        }

        return "The machine has stopped due to an error: \(error.localizedDescription)"
    }
    
    @ViewBuilder
    private var circularStartButton: some View {
        Button {
            if controller.canStart {
                Task { await ui.startOrResume() }
            } else if controller.canResume {
                Task {
                    try? await controller.resume()
                }
            }
        } label: {
            Image(systemName: "play")
        }
        .buttonStyle(VMCircularButtonStyle())
        .help(controller.state.isSaved ? "Resume" : "Start")
    }

    @ViewBuilder
    private var backgroundView: some View {
        VirtualMachineSessionBackgroundView(
            content: controller.virtualMachineModel.blurHashBackgroundContent,
            isRunning: controller.isRunning
        )
        .ignoresSafeArea()
    }

    /// Closing the window saves the virtual machine (or shuts it down when it can't be saved) before the window goes away.
    private var confirmBeforeClosing: () async -> Bool {
        { [weak ui] in
            guard let ui else { return true }

            return await ui.requestClose()
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
        configuration.label
            .font(.system(size: 50, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(30)
            .symbolVariant(.fill)
            .airMaterialBackground(
                visualEffect: configuration.isPressed ? .selection : .hudWindow,
                glassEffect: .clear.tint(configuration.isPressed ? Color.white.opacity(0.2) : nil),
                in: Circle()
            )
            .contentShape(Circle())
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
        if let savedScreenshot {
            .customImage(savedScreenshot)
        } else if let thumbnail {
            .customImage(thumbnail)
        } else {
            .blurHash(metadata.backgroundHash)
        }
    }
}

private extension Error {
    var isMaximumActiveVirtualMachinesError: Bool {
        let nsError = self as NSError

        guard nsError.domain == "VZErrorDomain" else { return false }

        if nsError.code == 6 { return true }

        if let reason = nsError.localizedFailureReason,
           reason.localizedCaseInsensitiveContains("maximum supported number of active virtual machines") {
            return true
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("maximum supported number of active virtual machines")
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
            .environment(VMLibraryController.preview.templatesController)
    }
}

#Preview {
    VirtualMachineSessionViewPreview()
}
#endif
