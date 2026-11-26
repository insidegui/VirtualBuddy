import SwiftUI
import VirtualCore
import VirtualWormhole

/// Only edits resources that the current VM can change without rebuilding its device topology.
struct VMLiveConfigurationView: View {
    @ObservedObject var controller: VMController
    private let tunnels: VMLiveServiceTunnelsModel
    @State private var editor: VMLiveConfigurationEditor

    init(controller: VMController, tunnels: VMLiveServiceTunnelsModel) {
        self.controller = controller
        self.tunnels = tunnels
        _editor = State(initialValue: VMLiveConfigurationEditor(controller: controller))
    }

    private var resolvedRestoreImage: ResolvedRestoreImage? {
        let vm = controller.virtualMachineModel
        let catalog = SoftwareCatalog.current(for: vm.configuration.systemType)
        if let url = vm.metadata.remoteInstallImageURL,
           let image = catalog.resolvedRestoreImage(matching: url, guestType: vm.configuration.systemType) {
            return image
        }
        return vm.metadata.installImageURL.flatMap {
            catalog.resolvedRestoreImage(matching: $0, guestType: vm.configuration.systemType)
        }
    }

    var body: some View {
        @Bindable var editor = editor

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConfigurationSection(collapsingDisabled: true) {
                    SharedFoldersManagementView(configuration: $editor.configuration)
                        .disabled(!controller.canEditLiveSharedFolders)
                } header: {
                    SummaryHeader("Sharing", systemImage: "folder", summary: controller.liveConfiguration.sharingSummary)
                }

                if controller.liveConfiguration.systemType == .mac {
                    VMLiveServiceTunnelsSection(controller: controller, model: tunnels)
                }

                if let display = controller.liveConfiguration.hardware.displayDevices.first {
                    VMLiveDisplayConfigurationView(
                        device: display,
                        canChangePPI: controller.liveConfiguration.systemType.supportsDisplayPPI,
                        apply: editor.updateDisplay
                    )
                    .id(display.id)
                    .disabled(!controller.canEditLiveDisplay)
                    if !VBDisplayDevice.automaticallyReconfiguresDisplaySupportedByHost {
                        Text("Changing display settings while running requires macOS 14 or later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !controller.canEditLiveConfiguration {
                    Text("Settings are unavailable while the virtual machine is changing state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(20)
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 380, idealHeight: 460)
        .environment(\.vmConfigurationContext, .live)
        .environment(\.configurationGuestType, controller.liveConfiguration.systemType)
        .environment(\.resolvedRestoreImage, resolvedRestoreImage)
        .windowTitle("\(controller.virtualMachineModel.name) — Settings")
        .windowStyleMask([.titled, .closable, .resizable])
        .alert("Unable to Update Settings", isPresented: $editor.isShowingError) {
            Button("OK", role: .cancel) { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
        .closesWindowWhenSessionEnds(controller)
    }
}

@Observable
@MainActor
private final class VMLiveConfigurationEditor {
    let controller: VMController
    var errorMessage: String?

    init(controller: VMController) {
        self.controller = controller
    }

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func updateDisplay(_ device: VBDisplayDevice) {
        do {
            try controller.updateLiveDisplay(device)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var configuration: VBMacConfiguration {
        get { controller.liveConfiguration }
        set {
            do {
                try controller.updateLiveSharedFolders(newValue.sharedFolders)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview {
    let controller = VMController(with: .preview, library: .preview)

    VMLiveConfigurationView(controller: controller, tunnels: VMLiveServiceTunnelsModel(controller: controller))
}
#endif
