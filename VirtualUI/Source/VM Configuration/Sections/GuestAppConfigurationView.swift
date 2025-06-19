//
//  GuestAppConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 19/06/25.
//

import SwiftUI
import VirtualCore

struct GuestAppConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable VirtualBuddy Guest App", isOn: $configuration.guestAdditionsEnabled)

            Text("""
            The guest app mounts shared directories and shares the clipboard between your Mac and virtual machines.

            To install the app in your virtual machine, look for a disk image named “Guest” in the Finder sidebar. \
            Double-click the VirtualBuddyGuest app icon to install the app. 
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#if DEBUG
#Preview {
    _ConfigurationSectionPreview { GuestAppConfigurationView(configuration: $0) }
}
#endif
