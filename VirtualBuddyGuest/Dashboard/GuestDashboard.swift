//
//  ContentView.swift
//  VirtualBuddyGuest
//
//  Created by Guilherme Rambo on 02/06/22.
//

import SwiftUI
import VirtualWormhole

struct GuestDashboard: View {
    @EnvironmentObject private var launchAtLoginManager: GuestLaunchAtLoginManager
    @EnvironmentObject private var hostConnection: WormholeManager
    @EnvironmentObject private var sharedFolders: GuestSharedFoldersManager

    @State var activated = false

    #if ENABLE_USERDEFAULTS_SYNC
    @State private var showingDefaultsPopover = false
    #endif

    var body: some View {
        VStack {
            connectionState

            sharedFoldersState

            Spacer()

            Form {
                Toggle("Launch At Login", isOn: launchAtLoginBinding)

                #if ENABLE_USERDEFAULTS_SYNC
                Button("Defaults Import…") {
                    showingDefaultsPopover.toggle()
                }
                .popover(isPresented: $showingDefaultsPopover) {
                    GuestDefaultsImportView()
                }
                #endif
            }

            Spacer()
        }
            .padding()
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
    }

    @ViewBuilder
    private var connectionState: some View {
        HStack(spacing: 4) {
            Circle()
                .foregroundColor(hostConnection.isConnected ? Color.green : Color.red)
                .frame(width: 6)

            if hostConnection.isConnected {
                Text("Connected to VirtualBuddy")
            } else {
                Text("Not Connected")
            }
        }
        .foregroundStyle(.secondary)
        .font(.caption)
    }

    @ViewBuilder
    private var sharedFoldersState: some View {
        if let error = sharedFolders.error {
            VStack {
                Text("Failed to mount shared folders:")
                    .foregroundColor(.secondary)
                Text(error.localizedDescription)
                    .foregroundColor(.red)
            }
        } else {
            HStack {
                Text("Shared Folders:")
                Button("Reveal in Finder") {
                    sharedFolders.revealInFinder()
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        .init {
            launchAtLoginManager.isLaunchAtLoginEnabled
        } set: { newValue in
            Task {
                do {
                    try await launchAtLoginManager.setLaunchAtLoginEnabled(newValue)
                } catch {
                    await MainActor.run {
                        _ = NSAlert(error: error).runModal()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct GuestDashboard_Previews: PreviewProvider {
    static var previews: some View {
        GuestDashboard()
            .environmentObject(GuestLaunchAtLoginManager())
            .environmentObject(WormholeManager.sharedGuest)
            .environmentObject(GuestSharedFoldersManager())
    }
}

final class MockHostConnectionStateProvider: HostConnectionStateProvider {
    var isConnected: Bool = false
}
#endif
