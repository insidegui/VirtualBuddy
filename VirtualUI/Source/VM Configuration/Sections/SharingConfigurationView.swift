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
        Text("Sharing options go here")
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
    static var previews: some View {
        _Template(config: VBMacConfiguration.default)
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
