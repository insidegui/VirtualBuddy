//
//  NetworkConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct NetworkConfigurationView: View {
    
    @Binding var hardware: VBMacDevice

    @State private var previousMACAddress: String?

    init(hardware: Binding<VBMacDevice>) {
        self._hardware = hardware
        self._previousMACAddress = .init(wrappedValue: hardware.wrappedValue.networkDevices.first?.macAddress)
    }

    private var kind: Binding<VBNetworkDevice.Kind?> {
        .init {
            hardware.networkDevices.first?.kind
        } set: { newValue in
            if let newValue {
                if hardware.networkDevices.isEmpty {
                    hardware.networkDevices = [.default]
                }
                hardware.networkDevices[0].kind = newValue
                if let previousMACAddress {
                    hardware.networkDevices[0].macAddress = previousMACAddress
                }
            } else {
                hardware.networkDevices.removeAll()
            }
        }

    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            typePicker

            if let kind = kind.wrappedValue {
                switch kind {
                case .NAT:
                    natSettings
                case .bridge:
                    bridgeSettings
                }
            } else {
                Text("This virtual machine won't have any access to the network.")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: kind) {
            Text("None")
                .tag(Optional<VBNetworkDevice.Kind>.none)

            ForEach(VBNetworkDevice.Kind.allCases) { kind in
                Text(kind.name)
                    .tag(Optional<VBNetworkDevice.Kind>.some(kind))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("The type of network device")
    }
    
    @ViewBuilder
    private var macAddressField: some View {
        PropertyControl("MAC Address") {
            EphemeralTextField($hardware.networkDevices[0].macAddress, alignment: .leading) { addr in
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
        .onChange(of: hardware.networkDevices[0].macAddress) { newValue in
            previousMACAddress = newValue
        }
    }
    
    @State private var bridgeInterfaces: [VBNetworkDeviceBridgeInterface] = []
    
    @ViewBuilder
    private var natSettings: some View {
        macAddressField
    }
    
    @ViewBuilder
    private var bridgeSettings: some View {
        if VBNetworkDevice.appSupportsBridgedNetworking {
            PropertyControl("Interface") {
                HStack {
                    Picker("Interface", selection: $hardware.networkDevices[0].id) {
                        if bridgeInterfaces.isEmpty {
                            Text("No Interfaces Available")
                                .tag(hardware.networkDevices[0].id)
                        } else {
                            ForEach(bridgeInterfaces) { iface in
                                Text(iface.name)
                                    .tag(iface.id)
                            }
                        }
                    }
                    .disabled(bridgeInterfaces.isEmpty)
                    
                    Spacer()
                    
                    Button {
                        bridgeInterfaces = VBNetworkDevice.bridgeInterfaces
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reload interfaces")
                }
                .onAppear {
                    bridgeInterfaces = VBNetworkDevice.bridgeInterfaces
                }
            }
            
            macAddressField
        } else {
            Text(VBNetworkDevice.bridgeUnsupportedMessage)
                .foregroundColor(.red)
        }
    }
}

#if DEBUG

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _ConfigurationSectionPreview(.networkPreviewNAT) {
            NetworkConfigurationView(hardware: $0.hardware)
        }
        .previewDisplayName("NAT")

        _ConfigurationSectionPreview(.networkPreviewBridge) {
            NetworkConfigurationView(hardware: $0.hardware)
        }
        .previewDisplayName("Bridge")
        
        _ConfigurationSectionPreview(.networkPreviewNone) {
            NetworkConfigurationView(hardware: $0.hardware)
        }
        .previewDisplayName("None")
    }
}
#endif
