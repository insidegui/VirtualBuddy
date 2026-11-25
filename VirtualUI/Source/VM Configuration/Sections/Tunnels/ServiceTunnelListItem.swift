import SwiftUI
import VirtualWormhole

/// A row describing a single service tunnel, used by both the host's tunnel configuration and the guest's tunnel list.
struct ServiceTunnelListItem<Accessory: View>: View {
    let tunnel: ServiceTunnel
    var status: String?
    /// When `nil`, the row is read-only and doesn't offer a checkbox for enabling/disabling the tunnel.
    var isEnabled: Binding<Bool>?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            if let isEnabled {
                Toggle("Enable tunnel", isOn: isEnabled)
                    .labelsHidden()
                    .help("Enable/disable this tunnel")
                    .controlSize(.small)
            }

            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Text(verbatim: tunnel.listener.address)

                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)

                    Text(verbatim: tunnel.destination.address)
                }
                .monospacedDigit()

                Text(verbatim: caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .opacity(tunnel.isEnabled ? 1 : 0.8)
            .help(tunnel.description)

            Spacer(minLength: 8)

            accessory()
        }
        .padding(.vertical, 6)
        /// Easier to hit trailing edge buttons without hovering floating scroll bar.
        .padding(.trailing, 4)
        .contentShape(.rect)
    }

    private var caption: String {
        let direction = "\(tunnel.listenerSideName) to \(tunnel.destinationSideName)"

        if !tunnel.isEnabled, isEnabled == nil {
            return "\(direction) · Off"
        } else if tunnel.isEnabled, let status {
            return "\(direction) · \(status)"
        } else {
            return direction
        }
    }
}

extension ServiceTunnelListItem where Accessory == EmptyView {
    init(tunnel: ServiceTunnel, status: String? = nil, isEnabled: Binding<Bool>? = nil) {
        self.init(tunnel: tunnel, status: status, isEnabled: isEnabled, accessory: { EmptyView() })
    }
}

extension ServiceTunnel {
    var listenerSideName: String { listensOnHost ? "Host" : "Guest" }
    var destinationSideName: String { listensOnHost ? "Guest" : "Host" }
}

#if DEBUG
extension ServiceTunnel {
    static let previewWebServer = ServiceTunnel(listensOnHost: true, listener: .tcp(8080), destination: .tcp(3000))
    static let previewDatabase = ServiceTunnel(listensOnHost: false, listener: .tcp6(5432), destination: .tcp(5432))
    static let previewUnixSocket = ServiceTunnel(listensOnHost: true, listener: .unix("/Users/steve/Library/Application Support/Sockets/agent.sock"), destination: .unix("/var/run/agent.sock"))
    static let previewDisabled: ServiceTunnel = {
        var tunnel = ServiceTunnel(listensOnHost: true, listener: .tcp(2222), destination: .tcp(22))
        tunnel.isEnabled = false
        return tunnel
    }()

    static let previewTunnels: [ServiceTunnel] = [.previewWebServer, .previewDatabase, .previewUnixSocket, .previewDisabled]
}
#endif
