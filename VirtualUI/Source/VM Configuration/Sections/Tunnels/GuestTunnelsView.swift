import SwiftUI
import VirtualWormhole

/// Lists the service tunnels for the virtual machine in VirtualBuddyGuest and allows requesting new ones from the host.
public struct GuestTunnelsView: View {
    let session: GuestHostSession

    public init(session: GuestHostSession) {
        self.session = session
    }

    public var body: some View {
        GuestTunnelsList(
            tunnels: session.tunnels.rules,
            requests: session.tunnels.requests,
            status: session.tunnels.status,
            isAvailable: session.tunnels.available
        ) {
            try await session.requestTunnel($0)
        }
    }
}

private struct GuestTunnelsList: View {
    let tunnels: [ServiceTunnel]
    let requests: [ServiceTunnel]
    let status: [ServiceTunnel.ID: String]
    let isAvailable: Bool
    let requestTunnel: (ServiceTunnel) async throws -> Void

    @State private var isShowingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupedList {
                List {
                    ForEach(tunnels) { tunnel in
                        ServiceTunnelListItem(tunnel: tunnel, status: status[tunnel.id])
                    }

                    ForEach(requests) { request in
                        ServiceTunnelListItem(tunnel: request, status: "Awaiting approval in VirtualBuddy")
                    }
                }
            } headerAccessory: {
                Text("Service Tunnels")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } footerAccessory: {
                EmptyView()
            } emptyOverlay: {
                emptyOverlay
            } addButton: { label in
                Button {
                    isShowingEditor = true
                } label: {
                    label.groupedListButtonLabel()
                }
                .help("Request service tunnel")
            } removeButton: { _ in
                EmptyView?.none
            }
            .disabled(!isAvailable)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity, minHeight: 320, idealHeight: 360, maxHeight: .infinity)
        .sheet(isPresented: $isShowingEditor) {
            ServiceTunnelEditor(mode: .request, existingTunnels: tunnels + requests, save: requestTunnel)
        }
    }

    private var footnote: String {
        if isAvailable {
            "Tunnels requested here must be approved in the virtual machine’s settings in VirtualBuddy on the host Mac."
        } else {
            "Service tunnels require a connection to a version of VirtualBuddy that supports them."
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if tunnels.isEmpty, requests.isEmpty {
            Text("No service tunnels configured.")

            if isAvailable {
                Button("Request Service Tunnel") {
                    isShowingEditor = true
                }
                .buttonStyle(.link)
            }
        }
    }
}

#if DEBUG
#Preview("Guest — Populated") {
    GuestTunnelsList(
        tunnels: [.previewWebServer, .previewUnixSocket],
        requests: [.previewDatabase],
        status: [ServiceTunnel.previewWebServer.id: "Listening"],
        isAvailable: true
    ) { _ in }
}

#Preview("Guest — Empty") {
    GuestTunnelsList(tunnels: [], requests: [], status: [:], isAvailable: true) { _ in }
}

#Preview("Guest — Unavailable") {
    GuestTunnelsList(tunnels: [], requests: [], status: [:], isAvailable: false) { _ in }
}
#endif
