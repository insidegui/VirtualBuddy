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
