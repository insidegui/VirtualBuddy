//
//  NetworkConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct NetworkConfigurationView: View {
    
    @Binding var device: VBNetworkDevice
    
    var body: some View {
        typePicker
            .padding(.bottom, 8)
        
        macAddressField
    }
    
    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $device.kind) {
            ForEach(VBNetworkDevice.Kind.allCases) { kind in
                Text(kind.name)
                    .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("The type of network device")
    }
    
    @ViewBuilder
    private var macAddressField: some View {
        VStack(alignment: .leading, spacing: 4) {
            PropertyControlLabel("MAC Address")
            EphemeralTextField($device.macAddress, alignment: .leading) { addr in
                Text(addr)
                    .textCase(.uppercase)
            } editableContent: { value in
                TextField("", text: .init(get: {
                    value.wrappedValue.uppercased()
                }, set: { value.wrappedValue = $0.uppercased() }))
            } validate: { value in
                return VBNetworkDevice.validateMAC(value)
            }
        }
    }
}
