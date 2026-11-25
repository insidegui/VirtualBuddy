import SwiftUI
import VirtualCore
import VirtualWormhole

/// Snapshot of the tunnel state reported by a running virtual machine's guest session.
struct ServiceTunnelsLiveState {
    var isAvailable = false
    var status: [ServiceTunnel.ID: String] = [:]
    /// Tunnels requested by VirtualBuddyGuest that are waiting for approval on the host.
    var requests: [ServiceTunnel] = []
}

extension ServiceTunnelsLiveState {
    @MainActor
    init(_ state: TunnelState) {
        self.init(isAvailable: state.available, status: state.status, requests: state.requests)
    }
}

extension ApprovedSettingState where Value == [ServiceTunnel] {
    /// Summary displayed in the header of the service tunnels configuration section.
    func summary(draft: [ServiceTunnel]? = nil) -> String {
        if draft == nil {
            switch self {
            case .needsApproval: return "Needs Review"
            case .unavailable: return "Unavailable"
            case .missing, .approved: break
            }
        }

        let count = (draft ?? reviewValue ?? []).count

        switch count {
        case 0: return "None"
        case 1: return "One Tunnel"
        default: return "\(count) Tunnels"
        }
    }
}

struct ServiceTunnelsConfigurationView: View {
    let settings: ApprovedSettingState<[ServiceTunnel]>
    /// Tunnels that have been edited but not saved yet, takes precedence over `settings`.
    var draft: [ServiceTunnel]? = nil
    /// State for the running virtual machine, `nil` when editing the configuration of a virtual machine that's not running.
    var liveState: ServiceTunnelsLiveState? = nil
    var decline: (ServiceTunnel.ID) -> Void = { _ in }
    let change: ([ServiceTunnel]) throws -> Void

    private enum EditorItem: Identifiable {
        case add
        case edit(ServiceTunnel)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let tunnel): tunnel.id.uuidString
            }
        }

        var original: ServiceTunnel? {
            guard case .edit(let tunnel) = self else { return nil }
            return tunnel
        }
    }

    @State private var selection = Set<ServiceTunnel.ID>()
    @State private var editor: EditorItem?
    /// A copy of the guest's request taken when the user chose to review it, which is what gets approved.
    @State private var requestBeingReviewed: ServiceTunnel?
    @State private var isShowingResetConfirmation = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    private var tunnels: [ServiceTunnel] { draft ?? settings.reviewValue ?? [] }

    private var requests: [ServiceTunnel] { liveState?.requests ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch (settings, draft) {
            case (.needsApproval, nil):
                reviewList

                reviewNotice
            case (.unavailable(let reason), nil):
                unavailableNotice(reason: reason)
            default:
                editableList

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Unable to Update Service Tunnels", isPresented: $isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Reset Service Tunnels", isPresented: $isShowingResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                apply([])
            }
        } message: {
            Text("The saved service tunnels for this virtual machine will be replaced with an empty list.")
        }
        .sheet(item: $requestBeingReviewed) { request in
            ServiceTunnelApprovalSheet(request: request) { reviewed in
                apply(tunnels + [reviewed])
            }
        }
        .sheet(item: $editor) { item in
            ServiceTunnelEditor(
                mode: item.original.map { .edit($0) } ?? .add,
                existingTunnels: tunnels.filter { $0.id != item.original?.id }
            ) { updatedTunnel in
                if let original = item.original {
                    try change(tunnels.map { $0.id == original.id ? updatedTunnel : $0 })
                } else {
                    try change(tunnels + [updatedTunnel])
                }
            }
        }
    }

    private var footnote: String {
        let description = "Service tunnels forward TCP ports and Unix sockets between your Mac and the virtual machine, even when its network is disabled."

        return if liveState?.isAvailable == true {
            description
        } else {
            description + " Tunnels run while VirtualBuddyGuest is connected."
        }
    }

    // MARK: - Editable List

    @ViewBuilder
    private var editableList: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach(tunnels) { tunnel in
                    ServiceTunnelListItem(
                        tunnel: tunnel,
                        status: liveState?.status[tunnel.id],
                        isEnabled: isEnabledBinding(for: tunnel)
                    ) {
                        Button {
                            editor = .edit(tunnel)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Tunnel settings")
                    }
                    .contextMenu { tunnelMenu(for: tunnel) }
                    .tag(tunnel.id)
                }

                ForEach(requests) { request in
                    ServiceTunnelListItem(tunnel: request, status: "Requested by VirtualBuddyGuest") {
                        HStack(spacing: 6) {
                            Button("Decline") {
                                decline(request.id)
                            }

                            Button("Allow…") {
                                requestBeingReviewed = request
                            }
                        }
                        .controlSize(.small)
                    }
                    .tag(request.id)
                }
            }
        } emptyOverlay: {
            emptyOverlay
        } addButton: { label in
            Button {
                editor = .add
            } label: {
                label.groupedListButtonLabel()
            }
            .help("Add service tunnel")
        } removeButton: { label in
            Button {
                removeSelection()
            } label: {
                label.groupedListButtonLabel()
            }
            .disabled(selection.isEmpty)
            .help("Remove selected tunnels")
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if tunnels.isEmpty, requests.isEmpty {
            Text("This VM has no service tunnels.")

            Button("Add Service Tunnel") {
                editor = .add
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func tunnelMenu(for tunnel: ServiceTunnel) -> some View {
        Toggle("Enabled", isOn: isEnabledBinding(for: tunnel))

        Button("Edit…") {
            editor = .edit(tunnel)
        }

        Divider()

        Button("Remove") {
            remove([tunnel.id])
        }
    }

    private func isEnabledBinding(for tunnel: ServiceTunnel) -> Binding<Bool> {
        Binding {
            tunnel.isEnabled
        } set: { isEnabled in
            var updatedTunnels = tunnels
            guard let index = updatedTunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }
            updatedTunnels[index].isEnabled = isEnabled
            apply(updatedTunnels)
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewList: some View {
        GroupedList {
            List {
                ForEach(tunnels) { tunnel in
                    ServiceTunnelDetail(tunnel: tunnel)
                        .padding(.vertical, 6)
                }
            }
        }
        /// Rows show their endpoints in full, so more room is needed to see a few of them at once.
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private var reviewNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("These service tunnels have not been approved on this Mac. Review them before allowing the virtual machine to use them.", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            HStack {
                Button("Approve Tunnels") {
                    apply(tunnels)
                }

                Button("Discard…") {
                    isShowingResetConfirmation = true
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func unavailableNotice(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Service tunnels are unavailable.", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(verbatim: reason)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button("Reset Service Tunnels…") {
                isShowingResetConfirmation = true
            }
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    private func removeSelection() {
        remove(selection)
    }

    private func remove(_ identifiers: Set<ServiceTunnel.ID>) {
        for request in requests where identifiers.contains(request.id) {
            decline(request.id)
        }

        if tunnels.contains(where: { identifiers.contains($0.id) }) {
            apply(tunnels.filter { !identifiers.contains($0.id) })
        }

        selection.subtract(identifiers)
    }

    private func apply(_ updatedTunnels: [ServiceTunnel]) {
        do {
            try change(updatedTunnels)
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}

#if DEBUG
private struct ServiceTunnelsConfigurationPreview: View {
    @State var settings: ApprovedSettingState<[ServiceTunnel]>
    @State var liveState: ServiceTunnelsLiveState?

    var body: some View {
        ConfigurationSection(collapsingDisabled: true) {
            ServiceTunnelsConfigurationView(settings: settings, liveState: liveState) { requestID in
                liveState?.requests.removeAll(where: { $0.id == requestID })
            } change: { tunnels in
                settings = .approved(tunnels)
                liveState?.requests.removeAll(where: { request in tunnels.contains(where: { $0.id == request.id }) })
            }
        } header: {
            SummaryHeader("Service Tunnels", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", summary: settings.summary())
        }
        .font(.system(size: 12))
        .frame(width: VMConfigurationSheet.minWidth)
        .padding(30)
    }
}

#Preview("Tunnels — Populated") {
    ServiceTunnelsConfigurationPreview(settings: .approved(ServiceTunnel.previewTunnels))
}

#Preview("Tunnels — Empty") {
    ServiceTunnelsConfigurationPreview(settings: .missing)
}

#Preview("Tunnels — Live") {
    ServiceTunnelsConfigurationPreview(
        settings: .approved([.previewWebServer, .previewDisabled]),
        liveState: ServiceTunnelsLiveState(
            isAvailable: true,
            status: [ServiceTunnel.previewWebServer.id: "Listening"],
            requests: [.previewDatabase]
        )
    )
}

#Preview("Tunnels — Needs Review") {
    ServiceTunnelsConfigurationPreview(settings: .needsApproval(ServiceTunnel.previewTunnels))
}

#Preview("Tunnels — Unavailable") {
    ServiceTunnelsConfigurationPreview(settings: .unavailable("The saved tunnel settings could not be read."))
}
#endif
