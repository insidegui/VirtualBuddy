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
        clipboardSyncToggle

        sharedFoldersManager
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

    @ViewBuilder
    private var sharedFoldersManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shared Folders")

                Spacer()

                Button {
                    addFolder()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.link)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            List {
                ForEach(configuration.sharedFolders) { folder in
                    Text(folder.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(folder.id)
                }
            }
//            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.top)
    }

    private func addFolder() {

    }
}

#if DEBUG
struct _ConfigurationSectionPreview<C: View>: View {

    var content: () -> C

    init(@ViewBuilder _ content: @escaping () -> C) {
        self.content = content
    }

    var body: some View {
        ConfigurationSection(collapsed: false, {
            content()
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
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99075")!, url: URL(fileURLWithPath: "/Users/insidegui/Downloads"), isReadOnly: false)
        ]
        return c
    }

    static var previews: some View {
        _Template(config: config)
    }

    struct _Template: View {
        @State var config: VBMacConfiguration
        init(config: VBMacConfiguration) {
            self._config = .init(wrappedValue: config)
        }
        var body: some View {
            _ConfigurationSectionPreview {
                SharingConfigurationView(configuration: $config)
            }
        }
    }
}
#endif
