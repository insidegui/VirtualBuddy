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
        #if ENABLE_SPICE_CLIPBOARD_SYNC
        clipboardSyncToggle
            .padding(.bottom)
        #endif

        SharedFoldersManagementView(configuration: $configuration)
    }

    @ViewBuilder
    private var clipboardSyncToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Clipboard Sync", isOn: $configuration.sharedClipboardEnabled)
                .disabled(!VBMacConfiguration.isNativeClipboardSharingSupported)

            Text(VBMacConfiguration.clipboardSharingNotice)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#if DEBUG
struct _ConfigurationSectionPreview<C: View>: View {

    @State private var config: VBMacConfiguration
    var content: (Binding<VBMacConfiguration>) -> C

    init(_ config: VBMacConfiguration = .default, @ViewBuilder _ content: @escaping (Binding<VBMacConfiguration>) -> C) {
        self._config = .init(wrappedValue: config)
        self.content = content
    }

    var body: some View {
        ConfigurationSection(.constant(false), {
            content($config)
        }, header: {
            Label("SwiftUI Preview", systemImage: "eye")
        })

        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
            .padding()
            .controlGroup()
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct SharingConfigurationView_Previews: PreviewProvider {
    static var config: VBMacConfiguration {
        var c = VBMacConfiguration.default
        c.sharedFolders = [
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99074")!, url: URL(fileURLWithPath: "/Users/insidegui/Desktop"), isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99075")!, url: URL(fileURLWithPath: "/Users/insidegui/Downloads"), isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99076")!, url: URL(fileURLWithPath: "/Volumes/Rambo/Movies"), isEnabled: false, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99077")!, url: URL(fileURLWithPath: "/Some/Invalid/Path"), isEnabled: true, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99078")!, url: URL(fileURLWithPath: "/Users/insidegui/Music"), isEnabled: true, isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99079")!, url: URL(fileURLWithPath: "/Users/insidegui/Developer"), isEnabled: true, isReadOnly: true),
        ]
        return c
    }

    static var previews: some View {
        _ConfigurationSectionPreview(config) { SharingConfigurationView(configuration: $0) }
        
        _ConfigurationSectionPreview(.default) { SharingConfigurationView(configuration: $0) }
            .previewDisplayName("Empty")
    }
}
#endif
