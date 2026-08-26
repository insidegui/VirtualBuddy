import SwiftUI
import VirtualCore

private enum USBDeviceAdditionMode: String, Identifiable {
    case browse
    case manual

    var id: Self { self }
}

@Observable
@MainActor
private final class USBDeviceBrowserModel {
    var devices = [VBHostUSBDevice]()
    var selectedDeviceID: VBHostUSBDevice.ID?

    @ObservationIgnored private let deviceProvider: () -> [VBHostUSBDevice]

    init(deviceProvider: @escaping () -> [VBHostUSBDevice] = VBHostUSBDeviceDiscovery.connectedDevices) {
        self.deviceProvider = deviceProvider
    }

    func refresh() {
        devices = deviceProvider()

        if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
            self.selectedDeviceID = nil
        }
    }
}

struct USBDevicesConfigurationView: View {
    @Binding var hardware: VBMacDevice

    @Environment(\.resolvedRestoreImage)
    private var resolvedRestoreImage

    @State private var additionMode: USBDeviceAdditionMode?

    private var feature: ResolvedVirtualizationFeature? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.usbPassthrough)
    }

    private var isUnsupported: Bool {
        !VBMacConfiguration.hostSupportsUSBPassthrough || feature?.status.isUnsupported == true
    }

    private var supportMessage: String? {
        if !VBMacConfiguration.hostSupportsUSBPassthrough {
            return VBMacConfiguration.usbPassthroughUnsupportedHostNotice
        }

        return feature?.status.supportMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hardware.usbDevices.isEmpty {
                Text("No host USB devices are configured for this virtual machine.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(hardware.usbDevices) { device in
                        USBConfiguredDeviceRow(device: device) {
                            hardware.usbDevices.removeAll { $0.id == device.id }
                        }

                        if device.id != hardware.usbDevices.last?.id {
                            Divider()
                        }
                    }
                }
            }

            HStack {
                Menu {
                    Button("Choose Connected Device…") {
                        additionMode = .browse
                    }

                    Button("Enter Vendor and Product IDs…") {
                        additionMode = .manual
                    }
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }

            Text("When the virtual machine is running, use the Accessory Access menu in the menu bar to grant VirtualBuddy access to a device.")
                .foregroundStyle(.secondary)

            if isUnsupported, let supportMessage {
                Text(supportMessage)
                    .foregroundStyle(VBMacConfiguration.hostSupportsUSBPassthrough ? .yellow : .red)
            }
        }
        .disabled(isUnsupported)
        .sheet(item: $additionMode) { mode in
            switch mode {
            case .browse:
                USBDeviceBrowserSheet(
                    existingDeviceIDs: Set(hardware.usbDevices.map(\.id)),
                    onAdd: add
                )
            case .manual:
                USBDeviceManualEntrySheet(
                    existingDeviceIDs: Set(hardware.usbDevices.map(\.id)),
                    onAdd: add
                )
            }
        }
    }

    private func add(_ device: VBUSBDevice) {
        guard !hardware.usbDevices.contains(where: { $0.id == device.id }) else { return }
        hardware.usbDevices.append(device)
    }
}

private struct USBConfiguredDeviceRow: View {
    let device: VBUSBDevice
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let name = device.name {
                    Text(name)
                } else {
                    Text("USB Device")
                }

                Text(verbatim: usbIdentifierDescription(vendorID: device.vendorID, productID: device.productID))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Label("Remove Device", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help("Remove USB device")
        }
        .padding(.vertical, 6)
    }
}

private struct USBDeviceBrowserSheet: View {
    let existingDeviceIDs: Set<VBUSBDevice.ID>
    let onAdd: (VBUSBDevice) -> Void

    @State private var model: USBDeviceBrowserModel

    @Environment(\.dismiss)
    private var dismiss

    private var selectedDevice: VBHostUSBDevice? {
        guard let selectedDeviceID = model.selectedDeviceID else { return nil }
        return model.devices.first { $0.id == selectedDeviceID }
    }

    init(
        existingDeviceIDs: Set<VBUSBDevice.ID>,
        deviceProvider: @escaping () -> [VBHostUSBDevice] = VBHostUSBDeviceDiscovery.connectedDevices,
        onAdd: @escaping (VBUSBDevice) -> Void
    ) {
        self.existingDeviceIDs = existingDeviceIDs
        self.onAdd = onAdd
        self._model = State(initialValue: USBDeviceBrowserModel(deviceProvider: deviceProvider))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            VStack(spacing: 0) {
                if model.devices.isEmpty {
                    ContentUnavailableView(
                        "No USB Devices Found",
                        systemImage: "cable.connector.slash",
                        description: Text("Connect a USB device to this Mac, then reload the list.")
                    )
                } else {
                    List(model.devices, selection: $model.selectedDeviceID) { device in
                        USBHostDeviceRow(
                            device: device,
                            isAlreadyAdded: existingDeviceIDs.contains(
                                VBUSBDevice.ID(vendorID: device.vendorID, productID: device.productID)
                            )
                        )
                        .tag(device.id)
                    }
                }
            }
            .navigationTitle("Choose USB Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Reload Devices", systemImage: "arrow.clockwise")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let selectedDevice else { return }

                        onAdd(
                            VBUSBDevice(
                                vendorID: selectedDevice.vendorID,
                                productID: selectedDevice.productID,
                                name: selectedDevice.productName
                            )
                        )
                        dismiss()
                    }
                    .disabled(selectedDevice.map(isAlreadyAdded) != false)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .task {
            model.refresh()
        }
    }

    private func isAlreadyAdded(_ device: VBHostUSBDevice) -> Bool {
        existingDeviceIDs.contains(
            VBUSBDevice.ID(vendorID: device.vendorID, productID: device.productID)
        )
    }
}

private struct USBHostDeviceRow: View {
    let device: VBHostUSBDevice
    let isAlreadyAdded: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let productName = device.productName {
                    Text(productName)
                } else {
                    Text("USB Device")
                }

                HStack(spacing: 6) {
                    if let manufacturerName = device.manufacturerName {
                        Text(manufacturerName)
                    }

                    Text(verbatim: usbIdentifierDescription(vendorID: device.vendorID, productID: device.productID))
                        .monospaced()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isAlreadyAdded {
                Text("Added")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .disabled(isAlreadyAdded)
    }
}

private struct USBDeviceManualEntrySheet: View {
    private enum Field: Hashable {
        case vendorID
        case productID
    }

    private enum Validation: Equatable {
        case unvalidated
        case valid(UInt16)
        case invalid

        init(_ input: String) {
            if let identifier = VBUSBDevice.parseIdentifier(input) {
                self = .valid(identifier)
            } else {
                self = .invalid
            }
        }

        var value: UInt16? {
            guard case .valid(let identifier) = self else { return nil }
            return identifier
        }

        var isInvalid: Bool {
            self == .invalid
        }
    }

    let existingDeviceIDs: Set<VBUSBDevice.ID>
    let onAdd: (VBUSBDevice) -> Void

    @State private var vendorIDInput = ""
    @State private var productIDInput = ""
    @State private var vendorIDValidation = Validation.unvalidated
    @State private var productIDValidation = Validation.unvalidated
    @State private var isAddingDevice = false

    @FocusState private var focusedField: Field?

    @Environment(\.dismiss)
    private var dismiss

    private var vendorID: UInt16? { vendorIDValidation.value }
    private var productID: UInt16? { productIDValidation.value }

    private var deviceID: VBUSBDevice.ID? {
        guard let vendorID, let productID else { return nil }
        return VBUSBDevice.ID(vendorID: vendorID, productID: productID)
    }

    private var isDuplicate: Bool {
        deviceID.map(existingDeviceIDs.contains) == true
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Vendor ID") {
                    TextField("Decimal or hexadecimal", text: $vendorIDInput, prompt: Text("1234 / 0x12AB"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($focusedField, equals: .vendorID)
                        .submitLabel(.next)
                        .onSubmit(validateVendorID)
                        .onChange(of: vendorIDInput) { _, _ in
                            vendorIDValidation = .unvalidated
                        }
                }

                LabeledContent("Product ID") {
                    TextField("Decimal or hexadecimal", text: $productIDInput, prompt: Text("1234 / 0x12AB"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($focusedField, equals: .productID)
                        .submitLabel(.done)
                        .onSubmit { validateProductID(submit: true) }
                        .onChange(of: productIDInput) { _, _ in
                            productIDValidation = .unvalidated
                        }
                }

                Text("Enter decimal values such as 1452, or hexadecimal values such as 0x05AC. IDs must be between 0 and 65535.")
                    .foregroundStyle(.secondary)

                if vendorIDValidation.isInvalid || productIDValidation.isInvalid {
                    Text("Enter a valid USB vendor ID and product ID.")
                        .foregroundStyle(.red)
                } else if isDuplicate {
                    Text("This USB device is already in the configuration.")
                        .foregroundStyle(.yellow)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Enter USB Device IDs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addValidatedDevice)
                        .keyboardShortcut(.defaultAction)
                        .disabled(deviceID == nil || isDuplicate || isAddingDevice)
                }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                switch oldValue {
                case .vendorID: validateVendorID()
                case .productID: validateProductID()
                case nil: break
                }
            }
        }
        .frame(width: 480, height: 280)
    }

    private func validateVendorID() {
        let validation = Validation(vendorIDInput)
        vendorIDValidation = validation

        if validation.value != nil {
            focusedField = .productID
        }
    }

    private func validateProductID(submit: Bool = false) {
        let validation = Validation(productIDInput)
        productIDValidation = validation

        guard submit else { return }

        guard let vendorID, let productID = validation.value else { return }
        guard !existingDeviceIDs.contains(VBUSBDevice.ID(vendorID: vendorID, productID: productID)) else { return }

        addDevice(vendorID: vendorID, productID: productID)
    }

    private func addValidatedDevice() {
        guard let vendorID, let productID, !isDuplicate else { return }
        addDevice(vendorID: vendorID, productID: productID)
    }

    private func addDevice(vendorID: UInt16, productID: UInt16) {
        guard !isAddingDevice else { return }
        isAddingDevice = true

        onAdd(VBUSBDevice(vendorID: vendorID, productID: productID))
        dismiss()
    }
}

private func usbIdentifierDescription(vendorID: UInt16, productID: UInt16) -> String {
    String(format: "0x%04X : 0x%04X  (%u : %u)", vendorID, productID, vendorID, productID)
}

#if DEBUG
private enum USBDevicePreviewData {
    static let configuredDevices = [
        VBUSBDevice(vendorID: 0x0781, productID: 0x55AE, name: "SanDisk Extreme SSD"),
        VBUSBDevice(vendorID: 0x1050, productID: 0x0407, name: "USB Security Key"),
    ]

    static let hostDevices = [
        VBHostUSBDevice(
            id: 1,
            vendorID: 0x0781,
            productID: 0x55AE,
            productName: "Extreme SSD",
            manufacturerName: "SanDisk"
        ),
        VBHostUSBDevice(
            id: 2,
            vendorID: 0x1235,
            productID: 0x8218,
            productName: "USB Audio Interface",
            manufacturerName: "Focusrite"
        ),
    ]

    static var configuration: VBMacConfiguration {
        var configuration = VBMacConfiguration.preview
        configuration.hardware.usbDevices = configuredDevices
        return configuration
    }
}

#Preview("Configuration — Populated") {
    _ConfigurationSectionPreview(USBDevicePreviewData.configuration) {
        USBDevicesConfigurationView(hardware: $0.hardware)
    }
}

#Preview("Configuration — Empty") {
    _ConfigurationSectionPreview {
        USBDevicesConfigurationView(hardware: $0.hardware)
    }
}

#Preview("Connected Device Browser") {
    USBDeviceBrowserSheet(
        existingDeviceIDs: [USBDevicePreviewData.configuredDevices[0].id],
        deviceProvider: { USBDevicePreviewData.hostDevices },
        onAdd: { _ in }
    )
}

#Preview("Manual Entry") {
    USBDeviceManualEntrySheet(
        existingDeviceIDs: Set(USBDevicePreviewData.configuredDevices.map(\.id)),
        onAdd: { _ in }
    )
}
#endif
