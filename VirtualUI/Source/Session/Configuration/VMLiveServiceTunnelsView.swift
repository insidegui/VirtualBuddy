import Combine
import SwiftUI
import VirtualCore
import VirtualWormhole

/// The saved service tunnels of a running virtual machine.
///
/// Reading them goes to the disk and the keychain, so they're kept here instead of being read whenever a view updates.
/// The windows that edit the tunnels of a session share a single model, so that a change made in one of them
/// is never overwritten by what another one had before.
@Observable
@MainActor
final class VMLiveServiceTunnelsModel {
    private let controller: VMController

    private(set) var settings: ApprovedSettingState<[ServiceTunnel]>

    @ObservationIgnored private var revisionObservation: AnyCancellable?

    init(controller: VMController) {
        self.controller = controller
        self.settings = controller.virtualMachineModel.serviceTunnelSettings
        // An edit made from what was shown before would otherwise undo a tunnel the guest was allowed to add in the meantime.
        revisionObservation = controller.$liveTunnelsRevision.dropFirst().sink { [weak self] _ in
            // Published before the property changes, and what's read here doesn't depend on its value.
            self?.reload()
        }
    }

    func update(_ tunnels: [ServiceTunnel]) throws {
        try controller.updateLiveTunnels(tunnels)
        reload()
    }

    /// Picks up tunnels that were saved, or are reviewed differently, without an edit made here.
    private func reload() {
        settings = controller.virtualMachineModel.serviceTunnelSettings
    }
}

/// Edits the service tunnels of a running virtual machine and reviews the ones requested by its guest.
struct VMLiveServiceTunnelsSection: View {
    @ObservedObject var controller: VMController
    let model: VMLiveServiceTunnelsModel

    var body: some View {
        ConfigurationSection(collapsingDisabled: true) {
            ServiceTunnelsConfigurationView(
                settings: model.settings,
                liveState: controller.tunnelState.map(ServiceTunnelsLiveState.init),
                decline: controller.declineTunnel,
                loadSources: controller.serviceTunnelSources,
                change: model.update
            )
            .disabled(!controller.canEditLiveConfiguration)
        } header: {
            SummaryHeader("Service Tunnels", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", summary: model.settings.summary())
        }
    }
}

/// Only has the service tunnels from the settings of a running virtual machine,
/// for reviewing the tunnels requested by its guest without going through the other settings.
struct VMLiveServiceTunnelsView: View {
    @ObservedObject var controller: VMController
    let model: VMLiveServiceTunnelsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VMLiveServiceTunnelsSection(controller: controller, model: model)

                if !controller.canEditLiveConfiguration {
                    Text("Service tunnels are unavailable while the virtual machine is changing state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(20)
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 300, idealHeight: 360)
        .environment(\.vmConfigurationContext, .live)
        .environment(\.configurationGuestType, controller.liveConfiguration.systemType)
        .windowTitle("\(controller.virtualMachineModel.name) — Service Tunnels")
        .windowStyleMask([.titled, .closable, .resizable])
        .closesWindowWhenSessionEnds(controller)
    }
}

extension View {
    /// Closes the window showing the view once the virtual machine is no longer running, which is when its live settings stop applying.
    func closesWindowWhenSessionEnds(_ controller: VMController) -> some View {
        modifier(SessionEndWindowClosingModifier(controller: controller))
    }
}

private struct SessionEndWindowClosingModifier: ViewModifier {
    @ObservedObject var controller: VMController

    @Environment(\.closeWindow)
    private var closeWindow

    func body(content: Content) -> some View {
        content.onChange(of: controller.state) { _, state in
            if state.isStopped || state.isIdle || state.isSavedSessionPresentation {
                closeWindow()
            }
        }
    }
}

#if DEBUG
#Preview {
    let controller = VMController(with: .preview, library: .preview)

    VMLiveServiceTunnelsView(controller: controller, model: VMLiveServiceTunnelsModel(controller: controller))
}
#endif
