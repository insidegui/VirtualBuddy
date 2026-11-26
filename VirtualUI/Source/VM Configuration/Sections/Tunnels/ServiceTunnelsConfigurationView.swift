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
    /// Provides the tunnels from other virtual machines that can be added to this one.
    var loadSources: @MainActor () -> [ServiceTunnelSource] = { [] }
    /// Stands in for the organization's policy in previews. The policy in effect is used when this is `nil`.
    var policyOverride: ServiceTunnelPolicy? = nil
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

    @State private var policyMonitor = ServiceTunnelPolicyMonitor()
    @State private var selection = Set<ServiceTunnel.ID>()
    @State private var editor: EditorItem?
    /// A copy of the guest's request taken when the user chose to review it, which is what gets approved.
    @State private var requestBeingReviewed: ServiceTunnel?
    @State private var isShowingResetConfirmation = false
    @State private var isShowingError = false
    @State private var errorMessage = ""
    @State private var sources: [ServiceTunnelSource] = []

    @Environment(\.controlActiveState)
    private var controlActiveState

    private var tunnels: [ServiceTunnel] { draft ?? settings.reviewValue ?? [] }

    private var policy: ServiceTunnelPolicy { policyOverride ?? policyMonitor.policy }

    /// Tunnels the policy doesn't allow stay in the list, since they're still saved and work again once it does.
    /// The banner below the list says who is blocking them, which leaves the row enough room for its addresses.
    private func status(for tunnel: ServiceTunnel) -> String? {
        policy.permits(tunnel) ? liveState?.status[tunnel.id] : "Blocked"
    }

    private var requests: [ServiceTunnel] { liveState?.requests ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch (settings, draft) {
            case (.needsApproval, nil):
                Text("These service tunnels have not been approved on this Mac.")
                    .foregroundColor(.yellow)
                
                reviewList

                reviewButtons
            case (.unavailable(let reason), nil):
                unavailableNotice(reason: reason)
            default:
                editableList
                    .disabled(policy.tunnelsDisabled)

                if policy != .unrestricted {
                    ManagedRestrictionBannerView(title: policy.tunnelsDisabled
                        ? "Service tunnels are disabled by your organization."
                        : "Service tunnels are restricted by your organization.")
                }

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reloadSources)
        .onChange(of: controlActiveState) { _, state in
            /// Tunnels for other virtual machines can only change while another window has focus.
            guard state == .key else { return }
            reloadSources()
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
                existingTunnels: tunnels.filter { $0.id != item.original?.id },
                policy: policy
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
                        status: status(for: tunnel),
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
                            .tint(.red)

                            Button("Allow…") {
                                requestBeingReviewed = request
                            }
                            .tint(.green)
                        }
                        .controlSize(.small)
                    }
                    .tag(request.id)
                }
            }
        } emptyOverlay: {
            emptyOverlay
        } addButton: { label in
            addButton(label: label)
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

            if !sources.isEmpty {
                Menu {
                    sourcesMenu
                } label: {
                    Text("Add from Virtual Machine")
                        .foregroundStyle(.link)
                }
                /// Menus don't take the link button style that the other action in the overlay has.
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: - Adding from Other Virtual Machines

    /// Adding a tunnel is a single click for as long as there's nothing else to offer.
    @ViewBuilder
    private func addButton(label: Label<Text, Image>) -> some View {
        if sources.isEmpty {
            Button {
                editor = .add
            } label: {
                label.groupedListButtonLabel()
            }
            .help("Add service tunnel")
        } else {
            Menu {
                Button("New Tunnel…") {
                    editor = .add
                }

                Divider()

                Menu("Add from Virtual Machine") {
                    sourcesMenu
                }
            } label: {
                label.groupedListButtonLabel()
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add service tunnel")
        }
    }

    @ViewBuilder
    private var sourcesMenu: some View {
        ForEach(sources) { source in
            Menu(source.name) {
                let available = additions(from: source.tunnels)

                Button("All Tunnels (\(source.tunnels.count))") {
                    apply(tunnels + available)
                }
                .disabled(available.isEmpty)

                Divider()

                ForEach(source.tunnels) { tunnel in
                    let addition = additions(from: [tunnel])

                    Button {
                        apply(tunnels + addition)
                    } label: {
                        Text(verbatim: tunnel.menuTitle)
                    }
                    .disabled(addition.isEmpty)
                    .help(tunnel.description)
                }
            }
        }
    }

    /// Copies of the tunnels from another virtual machine that this one can take, leaving out those
    /// with a listener it already uses. They're independent from the originals, so changing one doesn't affect the other.
    private func additions(from sourceTunnels: [ServiceTunnel]) -> [ServiceTunnel] {
        var result = tunnels

        for sourceTunnel in sourceTunnels {
            var tunnel = ServiceTunnel(listensOnHost: sourceTunnel.listensOnHost, listener: sourceTunnel.listener, destination: sourceTunnel.destination)
            tunnel.isEnabled = sourceTunnel.isEnabled

            if tunnel.canAdd(to: result) {
                result.append(tunnel)
            }
        }

        return Array(result.dropFirst(tunnels.count))
    }

    private func reloadSources() {
        sources = loadSources()
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
    private var reviewButtons: some View {
        HStack {
            Button("Discard") {
                isShowingResetConfirmation = true
            }
            .tint(.red)

            Spacer()

            Button("Approve Tunnels") {
                apply(tunnels)
            }
            .tint(.green)
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

private extension ServiceTunnel {
    /// Describes the tunnel in a menu, where the system doesn't truncate titles,
    /// so a long socket path would otherwise make the menu as wide as the screen.
    var menuTitle: String {
        "\(listenerSideName)  \(listener.menuAddress) → \(destinationSideName)  \(destination.menuAddress)"
    }
}

private extension TunnelEndpoint {
    var menuAddress: String {
        address.truncatedInMiddle(toFit: 240, font: .menuFont(ofSize: 0))
    }
}

private extension String {
    /// Replaces as few characters as possible in the middle of the string with an ellipsis, so that it fits `width` when drawn with `font`.
    func truncatedInMiddle(toFit width: CGFloat, font: NSFont) -> String {
        func measure(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }

        guard measure(self) > width else { return self }

        func truncated(keeping characterCount: Int) -> String {
            "\(prefix((characterCount + 1) / 2))…\(suffix(characterCount / 2))"
        }

        /// The most characters that can be kept is somewhere in this range, found by halving it until a single candidate is left.
        var candidates = 0...(count - 1)

        while candidates.lowerBound < candidates.upperBound {
            let middle = (candidates.lowerBound + candidates.upperBound + 1) / 2

            if measure(truncated(keeping: middle)) <= width {
                candidates = middle...candidates.upperBound
            } else {
                candidates = candidates.lowerBound...(middle - 1)
            }
        }

        return truncated(keeping: candidates.lowerBound)
    }
}

#if DEBUG
private extension ServiceTunnelSource {
    static let previewSources = [
        ServiceTunnelSource(id: "preview-1", name: "macOS Development", tunnels: ServiceTunnel.previewTunnels),
        ServiceTunnelSource(id: "preview-2", name: "Continuous Integration", tunnels: [.previewDatabase, .previewLongUnixSocket]),
    ]
}

private struct ServiceTunnelsConfigurationPreview: View {
    @State var settings: ApprovedSettingState<[ServiceTunnel]>
    @State var liveState: ServiceTunnelsLiveState?
    var sources: [ServiceTunnelSource] = []

    var body: some View {
        ConfigurationSection(collapsingDisabled: true) {
            ServiceTunnelsConfigurationView(settings: settings, liveState: liveState, decline: { requestID in
                liveState?.requests.removeAll(where: { $0.id == requestID })
            }, loadSources: { sources }) { tunnels in
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

#Preview("Tunnels — Other Virtual Machines") {
    ServiceTunnelsConfigurationPreview(settings: .approved([.previewWebServer]), sources: ServiceTunnelSource.previewSources)
}

#Preview("Tunnels — Empty, Other Virtual Machines") {
    ServiceTunnelsConfigurationPreview(settings: .missing, sources: ServiceTunnelSource.previewSources)
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

#Preview("Tunnels — Restricted by Policy") {
    var policy = ServiceTunnelPolicy()
    policy.unixSocketsDisabled = true
    policy.setHostPorts(allowed: ["8000-8999"], denied: [])

    return ConfigurationSection(collapsingDisabled: true) {
        ServiceTunnelsConfigurationView(settings: .approved(ServiceTunnel.previewTunnels), policyOverride: policy) { _ in }
    } header: {
        SummaryHeader("Service Tunnels", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", summary: "4 Tunnels")
    }
    .font(.system(size: 12))
    .frame(width: VMConfigurationSheet.minWidth)
    .padding(30)
}

#Preview("Tunnels — Needs Review") {
    ServiceTunnelsConfigurationPreview(settings: .needsApproval(ServiceTunnel.previewTunnels))
}

#Preview("Tunnels — Unavailable") {
    ServiceTunnelsConfigurationPreview(settings: .unavailable("The saved tunnel settings could not be read."))
}
#endif
