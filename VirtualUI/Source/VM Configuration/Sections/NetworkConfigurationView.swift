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
        VStack(alignment: .leading, spacing: 16) {
            typePicker
            
            switch device.kind {
            case .NAT:
                natSettings
            case .bridge:
                bridgeSettings
            }
        }
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
        PropertyControl("MAC Address") {
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
                    Picker("Interface", selection: $device.id) {
                        if bridgeInterfaces.isEmpty {
                            Text("No Interfaces Available")
                                .tag(device.id)
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
            Text("Bridged network devices are not available in this build of the app.")
                .foregroundColor(.red)
        }
    }
}

#if DEBUG
struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        _Template(device: VBNetworkDevice(id: "Default", name: "Default", kind: .NAT, macAddress: "0A:82:7F:CE:C0:58"))
            .previewDisplayName("NAT")
        
        _Template(device: VBNetworkDevice(id: VBNetworkDevice.defaultBridgeInterfaceID ?? "ERROR", name: "Bridge", kind: .bridge, macAddress: "0A:82:7F:CE:C0:58"))
            .previewDisplayName("Bridge")
    }
    
    struct _Template: View {
        @State var device: VBNetworkDevice
        init(device: VBNetworkDevice) {
            self._device = .init(wrappedValue: device)
        }
        var body: some View {
            VStack(alignment: .leading) {
                NetworkConfigurationView(device: $device)
            }
            .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
                .padding()
                .controlGroup()
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
