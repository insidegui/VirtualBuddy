//
//  VirtualizationSettingsView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import BuddyKit

struct VirtualizationSettingsView: View {
    @Binding var settings: VBSettings

    #if DEBUG
    private var _forceShowBootImageFormatSettings: Bool { false }
    #endif

    private var showBootImageFormatSection: Bool {
        #if DEBUG
        guard !_forceShowBootImageFormatSettings else { return true }
        #endif

        return VBManagedDiskImage.Format.asif.isSupported
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Apple Signing Status Check", isOn: $settings.enableTSSCheck)
            } header: {
                Text("Signing Check")
            } footer: {
                SettingsFooter {
                    Text("Whether VirtualBuddy should verify macOS build signatures before downloading.")
                } helpText: {
                    Text("""
                    With this enabled, VirtualBuddy will check if the selected macOS build is being signed by Apple \
                    before attempting to download it.
                    
                    Unsigned builds can not be installed in virtual machines, so this saves time and bandwidth, \
                    allowing you to choose another version before waiting for the entire download and install attempt.
                    """)
                }
            }

            if showBootImageFormatSection {
                Section {
                    Picker("Boot Image Format", selection: $settings.bootDiskImagesUseASIF) {
                        Text("Most Efficient")
                            .tag(true)
                        Text("Most Compatible")
                            .tag(false)
                    }
                } header: {
                    Text("Disk Images")
                } footer: {
                    SettingsFooter {
                        Text("Select the disk image format for new virtual machines")
                    } helpText: {
                        Text("""
                        - **Most Efficient:** Uses the ASIF format. Requires macOS 26 or later on the host.
                        
                        - **Most Compatible:** Uses a raw image format, supported by all macOS versions.
                        
                        You should only change this setting if you plan on using the same virtual machines in hosts \
                        that are on macOS 15 or earlier.
                        """)
                    }
                }
            }
        }
        .navigationTitle(Text("Virtualization"))
    }
}

#if DEBUG
#Preview("Virtualization Settings") {
    SettingsScreen.preview(.virtualization)
}
#endif
