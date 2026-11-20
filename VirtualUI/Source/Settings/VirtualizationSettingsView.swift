//
//  VirtualizationSettingsView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import ManagedPreferencesUI

struct VirtualizationSettingsView: View {
    @Binding var settings: VBSettings

    @State private var showingManagedPreferences = false

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
        SettingsPane {
            SettingsRow("Signing status:") {
                Toggle("Check with Apple before downloading macOS", isOn: $settings.enableTSSCheck)
                SettingsCaption("VirtualBuddy can only install macOS builds that Apple is still signing. This check lets you choose another build before starting a download.")
            }

            if showBootImageFormatSection {
                SettingsDivider()

                SettingsRow("Boot disk format:") {
                    HStack {
                        Picker("Boot disk format", selection: $settings.bootDiskImagesUseASIF) {
                            Text("Most Efficient").tag(true)
                            Text("Most Compatible").tag(false)
                        }
                        .labelsHidden()
                        .fixedSize()

                        BootDiskFormatHelp()
                    }
                    SettingsCaption("Applies to boot disks created for new virtual machines.")
                }
            }

            SettingsDivider()

            SettingsRow("Device management:") {
                Button("Managed Preferences…") {
                    showingManagedPreferences = true
                }
                SettingsCaption("View the controls available to administrators and export their documentation or profile manifest.")
            }
        }
        .sheet(isPresented: $showingManagedPreferences) {
            VStack(spacing: 0) {
                ManagedPreferencesDocumentationView(VirtualBuddyManagedPreferences.schema)
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { showingManagedPreferences = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(width: 760, height: 520)
        }
    }
}

private struct BootDiskFormatHelp: View {
    @State private var isPresented = false

    var body: some View {
        HelpLink { isPresented.toggle() }
            .accessibilityLabel("About boot disk formats")
            .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**Most Efficient** uses the ASIF format and requires macOS 26 or later on the host.")
                    Text("**Most Compatible** uses a raw disk image. Choose this if you also run the virtual machine on a host with macOS 15 or earlier.")
                }
                .padding()
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
    }
}

#if DEBUG
#Preview("Virtualization Settings") {
    SettingsScreen.preview(.virtualization)
}

#Preview("Managed Preferences") {
    ManagedPreferencesDocumentationView(VirtualBuddyManagedPreferences.schema)
        .frame(width: 760, height: 460)
}
#endif
