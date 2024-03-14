//
//  SharingConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct SharingConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    var body: some View {
        SharedFoldersManagementView(configuration: $configuration)
    }
}

#if DEBUG
struct _ConfigurationSectionPreview<C: View>: View {

    @State private var config: VBMacConfiguration
    var content: (Binding<VBMacConfiguration>) -> C
    var ungrouped: Bool

    init(_ config: VBMacConfiguration = .preview, ungrouped: Bool = false, @ViewBuilder _ content: @escaping (Binding<VBMacConfiguration>) -> C) {
        self._config = .init(wrappedValue: config)
        self.ungrouped = ungrouped
        self.content = content
    }

    var body: some View {
        Group {
            if ungrouped {
                content($config)
            } else {
                ConfigurationSection(.constant(false), {
                    content($config)
                }, header: {
                    Label("SwiftUI Preview", systemImage: "eye")
                })
            }
        }
        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
            .padding()
            .controlGroup()
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct SharingConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview { SharingConfigurationView(configuration: $0) }

        _ConfigurationSectionPreview(.preview.linuxVirtualMachine) {
            SharingConfigurationView(configuration: $0) }
            .previewDisplayName("Linux Sharing Configuration View")

        _ConfigurationSectionPreview(.preview.removingSharedFolders) { SharingConfigurationView(configuration: $0) }
            .previewDisplayName("Empty")
    }
}
#endif
