//
//  ContentView.swift
//  VirtualBuddyGuest
//
//  Created by Guilherme Rambo on 02/06/22.
//

import SwiftUI
import VirtualWormhole

extension WormholeManager {
    static let shared = WormholeManager(for: .guest)
}

struct GuestDashboard<HostConnection>: View where HostConnection: HostConnectionStateProvider {
    @EnvironmentObject private var launchAtLoginManager: GuestLaunchAtLoginManager
    @EnvironmentObject private var hostConnection: HostConnection

    @State var activated = false
    
    var body: some View {
        VStack {
            connectionState

            Spacer()

            Form {
                Toggle("Launch At Login", isOn: launchAtLoginBinding)
            }

            Spacer()
        }
            .padding()
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .onAppear {
                _ = WormholeManager.shared
            }
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
        GuestDashboard<MockHostConnectionStateProvider>()
            .environmentObject(GuestLaunchAtLoginManager())
            .environmentObject(MockHostConnectionStateProvider())
    }
}

final class MockHostConnectionStateProvider: HostConnectionStateProvider {
    var isConnected: Bool = false
}
#endif
