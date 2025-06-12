//
//  NetworkConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore
import BuddyFoundation

enum NetworkDeviceSelection: Identifiable, Hashable {
    var id: String {
        switch self {
        case .disabled: "DISABLED"
        case .NAT: "NAT"
        case .bridge(let interfaceID): "BRIDGE_\(interfaceID)"
        }
    }

    case disabled
    case NAT
    case bridge(_ interface: VBNetworkDeviceInterface.ID)
}

struct NetworkConfigurationView: View {
    
    @Binding var hardware: VBMacDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NetworkDevicePicker(hardware: $hardware)

            if hardware.networkDevices.isEmpty {
                Text("This virtual machine will have no internet or local network access.")
                    .foregroundColor(.secondary)
            } else {
                macAddressField
            }
        }
    }
    
    @ViewBuilder
    private var macAddressField: some View {
        PropertyControl("MAC Address") {
            EphemeralTextField($hardware.networkMACAddress, alignment: .leading) { addr in
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

extension VBMacDevice {
    var networkDeviceSelection: NetworkDeviceSelection {
        get {
            if let device = networkDevices.first {
                switch device.kind {
                case .NAT: .NAT
                case .bridge: .bridge(device.id)
                }
            } else {
                .disabled
            }
        }
        set {
            let restoreMACAddress = networkMACAddress

            switch newValue {
            case .disabled:
                networkDevices.removeAll()
            case .NAT:
                networkDevices = [.default.withMACAddress(restoreMACAddress)]
            case .bridge(let id):
                networkDevices = [.init(id: id, name: id, kind: .bridge).withMACAddress(restoreMACAddress)]
            }
        }
    }

    var networkMACAddress: String {
        get {
            switch networkDeviceSelection {
            case .disabled: ""
            case .NAT, .bridge: networkDevices.first?.macAddress ?? ""
            }
        }
        set {
            switch networkDeviceSelection {
            case .disabled: break
            case .NAT, .bridge:
                guard !networkDevices.isEmpty else { return }
                networkDevices[0].macAddress = newValue
            }
        }
    }
}

extension VBNetworkDevice {
    func withMACAddress(_ address: String) -> VBNetworkDevice {
        guard !address.isEmpty else { return self }
        var mself = self
        mself.macAddress = address
        return mself
    }
}

struct NetworkDevicePicker: View {
    @Binding var hardware: VBMacDevice

    @State private var selectedOption: VBNetworkDeviceInterface?

    @State private var interfaces: [VBNetworkDeviceInterface] = [.automatic]

    var body: some View {
        PropertyControl("Interface") {
            HStack {
                Picker("Interface", selection: $hardware.networkDeviceSelection) {
                    Text("Disabled").tag(NetworkDeviceSelection.disabled)

                    Text("NAT").tag(NetworkDeviceSelection.NAT)

                    Section("Bridge") {
                        ForEach(interfaces) { interface in
                            Text(interface.name)
                                .tag(NetworkDeviceSelection.bridge(interface.id))
                        }
                    }
                }
                .labelsHidden()

                Spacer()

                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload interfaces")
            }
            .task { refresh() }
        }
    }

    private func refresh() {
        interfaces = [.automatic] + VBNetworkDevice.bridgeInterfaces
    }
}

#if DEBUG
#Preview {
    _ConfigurationSectionPreview(.networkPreviewNAT) {
        NetworkConfigurationView(hardware: $0.hardware)
    }
}
#endif
