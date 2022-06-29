//
//  VirtualMachineSessionView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore

struct VirtualMachineSessionView: View {
    @StateObject var controller: VMController
    @EnvironmentObject var library: VMLibraryController

    var body: some View {
        controllerStateView
            .edgesIgnoringSafeArea(.all)
            .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .background(backgroundView)
            .environmentObject(controller)
            .windowTitle(controller.virtualMachineModel.name)
            .windowStyleMask([.titled, .miniaturizable, .closable, .resizable])
            .confirmBeforeClosingWindow {
                guard controller.isStarting || controller.isRunning else { return true }

                let confirmed = await NSAlert.runConfirmationAlert(
                    title: "Stop Virtual Machine?",
                    message: "If you close the window now, the virtual machine will be stopped.",
                    continueButtonTitle: "Stop VM",
                    cancelButtonTitle: "Cancel"
                )

                guard confirmed else { return false }

                try? await controller.stop()

                return true
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
            captureSystemKeys: controller.options.captureSystemKeys
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
        ZStack {
            Color.black
            
            if let screenshot = controller.virtualMachineModel.screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .drawingGroup()
                    .saturation(1.3)
                    .brightness(-0.1)
                    .blur(radius: 22, opaque: true)
            }
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var toolbarContents: some View {
        HStack {
            pauseResumeToolbarButton
            
            if case .running = controller.state {
                Button {
                    Task { try await controller.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Shutdown")
                
                Button {
                    Task { try await controller.forceStop() }
                } label: {
                    Image(systemName: "exclamationmark.square.fill")
                }
                .help("Force stop")
            }

            Button {
                NSApp.sendAction(#selector(VirtualBuddyAppDelegate.restoreDefaultWindowPosition(_:)), to: nil, from: nil)
            } label: {
                Image(systemName: "macwindow")
            }
            .help("Restore default window size and position")
        }
    }
    
    @ViewBuilder
    private var pauseResumeToolbarButton: some View {
        if controller.canResume {
            Button {
                Task { try await controller.resume() }
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Resume")
        } else if controller.canPause {
            Button {
                Task { try await controller.pause() }
            } label: {
                Image(systemName: "pause.fill")
            }
            .help("Pause")
        } else {
            EmptyView()
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
    var isRunning: Bool {
        guard case .running = state else { return false }
        return true
    }
    var isStarting: Bool {
        guard case .starting = state else { return false }
        return true
    }
}

extension NSAlert {

    static func runConfirmationAlert(title: String,
                                     message: String,
                                     continueButtonTitle: String = "Continue",
                                     cancelButtonTitle: String = "Cancel") async -> Bool
    {
        let alert = NSAlert()

        alert.messageText = title
        alert.informativeText = message

        alert.addButton(withTitle: cancelButtonTitle)
        alert.addButton(withTitle: continueButtonTitle)

        let response: NSApplication.ModalResponse

        if let window = NSApp?.keyWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }

        return response == .alertSecondButtonReturn
    }

}
