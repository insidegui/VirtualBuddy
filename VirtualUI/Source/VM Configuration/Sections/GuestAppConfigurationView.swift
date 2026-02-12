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

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    private var guestAppStatus: ResolvedFeatureStatus? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.guestApp)?.status
    }

    private var guestAppUnsupported: Bool { guestAppStatus?.isUnsupported == true }
    private var guestAppHelp: String? {
        guestAppUnsupported ? (guestAppStatus?.supportMessage ?? "Not supported.") : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let guestAppHelp {
                    Toggle("Enable VirtualBuddy Guest App", isOn: $configuration.guestAdditionsEnabled)
                        .disabled(true)
                        .help(guestAppHelp)
                } else {
                    Toggle("Enable VirtualBuddy Guest App", isOn: $configuration.guestAdditionsEnabled)
                }
            }
            .onChange(of: guestAppUnsupported) { isUnsupported in
                if isUnsupported {
                    configuration.guestAdditionsEnabled = false
                }
            }
            .onAppear {
                if guestAppUnsupported {
                    configuration.guestAdditionsEnabled = false
                }
            }

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
