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

struct GuestDashboard: View {
    @EnvironmentObject private var launchAtLoginManager: GuestLaunchAtLoginManager

    @State var activated = false
    
    var body: some View {
        Form {
            Toggle("Launch At Login", isOn: launchAtLoginBinding)
        }
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .onAppear {
                _ = WormholeManager.shared
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
    }
}
#endif
