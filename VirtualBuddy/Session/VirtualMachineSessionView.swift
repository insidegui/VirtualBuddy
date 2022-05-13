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

    var body: some View {
        controllerStateView
            .edgesIgnoringSafeArea(.all)
            .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .background(Color.black)
            .cocoaToolbar { toolbarContents }
            .environmentObject(controller)
            .windowTitle(controller.virtualMachineModel.name)
            .windowStyleMask([.titled, .miniaturizable, .closable, .resizable])
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
        SwiftUIVMView(controllerState: .constant(.running(vm)))
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
    
    // MARK: - Toolbar Buttons
    
    private var toolbarContents: some View {
        HStack {
            pauseResumeToolbarButton
            
            if case .running = controller.state {
                Button {
                    Task { try await controller.forceStop() }
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
        ZStack {
            mainContent(with: configuration)
                .blendMode(.overlay)
                .opacity(1)
            mainContent(with: configuration)
                .opacity(0.9)
                .background(Circle().foregroundStyle(Material.thick))
        }
    }
    
    private func mainContent(with configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 50, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 4)
            .padding(30)
            .background(Circle().fill(Color.accentColor))
            .brightness(configuration.isPressed ? 0.3 : 0)
            .symbolVariant(.fill)
            .contentShape(Circle())
    }
    
}
