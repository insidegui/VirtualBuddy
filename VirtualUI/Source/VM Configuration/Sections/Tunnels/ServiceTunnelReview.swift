import SwiftUI
import VirtualWormhole

/// Describes a service tunnel in full, for the moment the host user decides whether to allow it.
///
/// Nothing is shortened here, unlike in ``ServiceTunnelListItem``: the user approves a tunnel by reading
/// its endpoints, so every character of them has to be on screen.
struct ServiceTunnelDetail: View {
    let tunnel: ServiceTunnel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            endpoint(tunnel.destination, title: "Service on \(tunnel.destinationSideName)")

            endpoint(tunnel.listener, title: "Reachable from \(tunnel.listenerSideName) at")

            if !tunnel.isEnabled {
                Text("This tunnel is turned off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if tunnel.listener.hasCharactersOutsideASCII || tunnel.destination.hasCharactersOutsideASCII {
                Label("A socket path in this tunnel has characters that can look identical to other characters. Make sure it's the location you expect.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func endpoint(_ endpoint: TunnelEndpoint, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(verbatim: endpoint.address)
                .monospaced()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension ServiceTunnel {
    /// What allowing the tunnel lets the other side do, in terms of the side that's exposed by it.
    var consequence: String {
        if listensOnHost {
            "Apps on this Mac that connect to \(listener.address) will be talking to the virtual machine, not to a service on this Mac."
        } else {
            "While the virtual machine is running, it will be able to connect to this service on your Mac. The service sees those connections as coming from an app on your Mac."
        }
    }
}

/// Asks the host user to confirm a tunnel requested by the guest before it's approved.
///
/// The sheet is given a copy of the request as it was when the user chose to review it, and approves that copy.
/// What the guest is requesting can change at any time, so approving whatever is currently requested
/// would let the guest replace the tunnel after the user has read it.
struct ServiceTunnelApprovalSheet: View {
    let request: ServiceTunnel
    let allow: (ServiceTunnel) -> Void

    /// Something on this Mac already has the address the tunnel would listen on. A request for such an address
    /// stands out, since apps on this Mac expecting that service are the ones that would reach the virtual machine instead.
    @State private var listenerIsOccupied = false

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ServiceTunnelDetail(tunnel: request)
                } header: {
                    Text("VirtualBuddyGuest in this virtual machine is requesting a service tunnel.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Text(request.consequence)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if listenerIsOccupied {
                        Label("Something on this Mac is already using \(request.listener.address). The tunnel won't start until that address is free.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Allow Service Tunnel?")
            .task {
                guard request.listensOnHost else { return }
                listenerIsOccupied = await request.listener.isOccupied()
            }
            .toolbar {
                /// Declining is the default action, so that pressing Return can't approve a tunnel.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow") {
                        allow(request)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Approval — Host Service") {
    ServiceTunnelApprovalSheet(request: .previewDatabase) { _ in }
}

#Preview("Approval — Long Unix Paths") {
    ServiceTunnelApprovalSheet(request: .previewLongUnixSocket) { _ in }
}

#Preview("Approval — Lookalike Path") {
    ServiceTunnelApprovalSheet(request: .previewLookalikeSocket) { _ in }
}
#endif
