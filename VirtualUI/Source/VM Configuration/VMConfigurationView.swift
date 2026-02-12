//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

extension EnvironmentValues {
    /// Type of guest that's currently being configured in a `VMConfigurationView`.
    @Entry fileprivate(set) var configurationGuestType: VBGuestType = .mac
}

private struct ResolvedRestoreImageKey: EnvironmentKey {
    static let defaultValue: ResolvedRestoreImage? = nil
}

extension EnvironmentValues {
    var resolvedRestoreImage: ResolvedRestoreImage? {
        get { self[ResolvedRestoreImageKey.self] }
        set { self[ResolvedRestoreImageKey.self] = newValue }
    }
}

enum CatalogFeatureID {
    static let fileSharing = "file_sharing"
    static let guestApp = "guest_app"
    static let trackpad = "trackpad"
    static let macKeyboard = "mac_keyboard"
    static let stateRestoration = "state_restoration"
    static let displayResize = "display_resize"
    static let rosettaSharing = "rosetta_sharing"
}

extension ResolvedRestoreImage {
    func feature(id: String) -> ResolvedVirtualizationFeature? {
        features.first { $0.id == id }
    }
}

extension ResolvedFeatureStatus {
    var supportMessage: String? {
        switch self {
        case .supported:
            return nil
        case .warning(let title, let message), .unsupported(let title, let message):
            return title ?? message
        }
    }

    var supportMessageColor: Color {
        switch self {
        case .supported:
            return .secondary
        case .warning:
            return .yellow
        case .unsupported:
            return .red
        }
    }
}

struct VMConfigurationView: View {
    @EnvironmentObject private var viewModel: VMConfigurationViewModel
    
    var initialConfiguration: VBMacConfiguration

    static var labelSpacing: CGFloat { 2 }

    @AppStorage("config.general.collapsed")
    private var generalCollapsed = true

    @AppStorage("config.storage.collapsed")
    private var storageCollapsed = true

    @AppStorage("config.display.collapsed")
    private var displayCollapsed = true
    
    @AppStorage("config.pointing.collapsed")
    private var pointingCollapsed = true
    
    @AppStorage("config.keyboard.collapsed")
    private var keyboardCollapsed = true

    @AppStorage("config.network.collapsed")
    private var networkCollapsed = true
    
    @AppStorage("config.sound.collapsed")
    private var soundCollapsed = true
    
    @AppStorage("config.sharing.collapsed")
    private var sharingCollapsed = true

    @AppStorage("config.guestApp.collapsed")
    private var guestAppCollapsed = true

    private var systemType: VBGuestType { viewModel.config.systemType }

    private var showBootDiskSection: Bool { viewModel.context == .preInstall }

    private var showPointingDeviceSection: Bool { systemType.supportsVirtualTrackpad }

    private var showKeyboardDeviceSection: Bool { systemType.supportsKeyboardCustomization }

    private var showDisplayPPISection: Bool { systemType.supportsDisplayPPI }

    private var showGuestAppSection: Bool { systemType.supportsGuestApp }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showBootDiskSection {
                bootDisk
            }

            general

            storage

            display

            if showPointingDeviceSection {
                pointingDevice
            }

            if showKeyboardDeviceSection {
                keyboardDevice
            }

            network

            sound

            if showGuestAppSection {
                guestApp
            }

            sharing
                .frame(minWidth: 0, idealWidth: VMConfigurationSheet.minWidth)
        }
        .font(.system(size: 12))
        .environment(\.configurationGuestType, viewModel.config.systemType)
        .environment(\.resolvedRestoreImage, viewModel.resolvedRestoreImage)
    }

    @ViewBuilder
    private var general: some View {
        ConfigurationSection($generalCollapsed) {
            HardwareConfigurationView(device: $viewModel.config.hardware)
        } header: {
            SummaryHeader(
                "General",
                systemImage: "memorychip",
                summary: viewModel.config.generalSummary
            )
        }
    }

    @ViewBuilder
    private var bootDisk: some View {
        ConfigurationSection(.constant(false), collapsingDisabled: true) {
            if let image = (try? viewModel.vm.bootDevice)?.managedImage {
                ManagedDiskImageEditor(image: image, isExistingDiskImage: false, isForBootVolume: true) { image in
                    viewModel.updateBootStorageDevice(with: image)
                }
            } else {
                Text("Something went terribly wrong: VM doesn't have a boot storage device with a managed disk image.")
                    .foregroundColor(.red)
            }
        } header: {
            SummaryHeader(
                "Boot Disk",
                systemImage: "wrench.and.screwdriver"
            )
        }
    }

    private var storageSummary: String {
        if showBootDiskSection {
            return viewModel.config.hardware.storageDevices.count == 1 ? "None" : viewModel.config.storageSummary
        } else {
            return viewModel.config.storageSummary
        }
    }

    @ViewBuilder
    private var storage: some View {
        ConfigurationSection($storageCollapsed) {
            StorageConfigurationView(hardware: $viewModel.config.hardware)
                .environmentObject(viewModel)
        } header: {
            SummaryHeader(
                showBootDiskSection ? "Additional Storage" : "Storage",
                systemImage: "externaldrive",
                summary: storageSummary
            )
        }
        .contextMenu {
            Button("Reset General Settings") {
                viewModel.config.hardware.cpuCount = initialConfiguration.hardware.cpuCount
                viewModel.config.hardware.memorySize = initialConfiguration.hardware.memorySize
            }
        }
    }

    @ViewBuilder
    private var display: some View {
        ConfigurationSection($displayCollapsed) {
            DisplayConfigurationView(
                device: $viewModel.config.hardware.displayDevices[0],
                selectedPreset: $viewModel.selectedDisplayPreset,
                canChangePPI: showDisplayPPISection
            )
        } header: {
            SummaryHeader("Display", systemImage: "display", summary: viewModel.config.displaySummary) {
                DisplayConfigurationView(
                    device: $viewModel.config.hardware.displayDevices[0],
                    selectedPreset: $viewModel.selectedDisplayPreset,
                    canChangePPI: showDisplayPPISection
                )
                .presetPicker
                .frame(width: 24)
            }
        }
    }
    
    @ViewBuilder
    private var pointingDevice: some View {
        ConfigurationSection($pointingCollapsed) {
            PointingDeviceConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            SummaryHeader(
                "Pointing Device",
                systemImage: "cursorarrow",
                summary: viewModel.config.pointingDeviceSummary
            )
        }
    }

    @ViewBuilder
    private var keyboardDevice: some View {
        ConfigurationSection($keyboardCollapsed) {
            KeyboardDeviceConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            SummaryHeader(
                "Keyboard Device",
                systemImage: "keyboard",
                summary: viewModel.config.keyboardDeviceSummary
            )
        }
    }

    @ViewBuilder
    private var network: some View {
        ConfigurationSection($networkCollapsed) {
            NetworkConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            SummaryHeader(
                "Network",
                systemImage: "network",
                summary: viewModel.config.networkSummary
            )
        }
    }

    @ViewBuilder
    private var sound: some View {
        ConfigurationSection($soundCollapsed) {
            SoundConfigurationView(hardware: $viewModel.config.hardware)
        } header: {
            SummaryHeader(
                "Sound",
                systemImage: viewModel.config.hardware.soundDevices.isEmpty ? "speaker.slash" : "speaker.3",
                summary: viewModel.config.soundSummary
            )
        }
    }

    @ViewBuilder
    private var sharing: some View {
        ConfigurationSection($sharingCollapsed) {
            SharingConfigurationView(configuration: $viewModel.config)
        } header: {
            SummaryHeader(
                "Sharing",
                systemImage: "folder",
                summary: viewModel.config.sharingSummary
            )
        }
    }

    @ViewBuilder
    private var guestApp: some View {
        ConfigurationSection($guestAppCollapsed) {
            GuestAppConfigurationView(configuration: $viewModel.config)
        } header: {
            SummaryHeader(
                "Guest App",
                summary: viewModel.config.guestAppSummary
            ) {
                Image(.guestSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15)
            }
        }
    }
}

// MARK: - Section Header

private struct SummaryHeader<Icon: View, Accessory: View>: View {
    var title: String
    var summary: String?
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, summary: String? = nil, @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.summary = summary
        self.icon = icon
        self.accessory = accessory
    }

    var body: some View {
        HStack {
            HStack {
                icon().frame(width: 22)

                Text(title)
            }
            accessory()

            Spacer()

            if let summary {
                Text(summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }
}

private extension SummaryHeader where Icon == Image {
    init(_ title: String, image: Image, summary: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.summary = summary
        self.icon = { image }
        self.accessory = accessory
    }

    init(_ title: String, systemImage: String, summary: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(title, image: Image(systemName: systemImage), summary: summary, accessory: accessory)
    }
}

private extension SummaryHeader where Icon == Image, Accessory == EmptyView {
    init(_ title: String, image: Image, summary: String? = nil) {
        self.init(title, image: image, summary: summary, accessory: { EmptyView() })
    }

    init(_ title: String, systemImage: String, summary: String? = nil) {
        self.init(title, systemImage: systemImage, summary: summary, accessory: { EmptyView() })
    }
}

private extension SummaryHeader where Accessory == EmptyView {
    init(_ title: String, summary: String? = nil, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title, summary: summary, icon: icon, accessory: { EmptyView() })
    }
}

#if DEBUG
struct VMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMConfigurationSheet_Previews.previews
    }
}
#endif
