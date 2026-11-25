import SwiftUI
import VirtualCore
import VirtualWormhole

struct HostTunnelsView: View {
    let settings: SignedSettingState<[ServiceTunnel]>
    var draft: [ServiceTunnel]? = nil
    private var rules: [ServiceTunnel] { draft ?? settings.reviewValue ?? [] }
    let state: TunnelState?
    var decline: (UUID) -> Void = { _ in }
    let change: ([ServiceTunnel]) throws -> Void

    private struct EditorItem: Identifiable {
        let original: ServiceTunnel?
        var id: UUID? { original?.id }
    }

    @State private var confirmingReset = false
    @State private var editor: EditorItem?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Service Tunnels").font(.headline)
            switch (settings, draft) {
            case (.needsApproval, nil):
                Text("Review these mappings before allowing them on this Mac.")
                ForEach(rules) { rule in
                    VStack(alignment: .leading) {
                        Text(rule.listensOnHost ? "Listen on Host Mac" : "Listen on Guest VM").font(.caption)
                        Text(verbatim: rule.listener.address).textSelection(.enabled)
                        Text(rule.listensOnHost ? "Connect to Guest VM" : "Connect to Host Mac").font(.caption)
                        Text(verbatim: rule.destination.address).textSelection(.enabled)
                        if !rule.isEnabled { Text("Off").font(.caption) }
                    }
                }
                HStack {
                    Button("Approve These Tunnels") { apply(rules) }
                    Button("Discard…") { confirmingReset = true }
                }
            case (.unavailable(let reason), nil):
                Text("Service tunnels are unavailable.").font(.headline)
                Text(verbatim: reason)
                Button("Reset Tunnel Settings…") { confirmingReset = true }
            default:
                mappingControls
            }
            if let error { Text(error).foregroundStyle(.red) }
            if state?.available != true {
                Text("Tunnels run while a compatible VirtualBuddyGuest is connected.").font(.caption)
            }
        }
        .confirmationDialog("Replace the saved tunnel configuration with an empty list?", isPresented: $confirmingReset) {
            Button("Reset Tunnel Settings", role: .destructive) { apply([]) }
        }
        .sheet(item: $editor) { item in
            let others = rules.filter { $0.id != item.original?.id }
            TunnelEditor(isGuest: false, rules: others, original: item.original) { replacement in
                if let original = item.original {
                    try change(rules.map { $0.id == original.id ? replacement : $0 })
                } else {
                    try change(rules + [replacement])
                }
                error = nil
            }
        }
    }

    @ViewBuilder
    private var mappingControls: some View {
        ForEach(rules) { rule in
            HStack {
                Toggle("Enable tunnel", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                    var updated = rules
                    guard let index = updated.firstIndex(where: { $0.id == rule.id }) else { return }
                    updated[index].isEnabled = enabled
                    apply(updated)
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                TunnelRow(rule: rule, status: state?.status[rule.id])
                Spacer()
                Button("Edit…") { editor = EditorItem(original: rule) }
                Button("Remove") { apply(rules.filter { $0.id != rule.id }) }
            }
        }
        ForEach(state?.requests ?? []) { request in
            VStack(alignment: .leading) {
                TunnelRow(rule: request, status: "Requested by VirtualBuddyGuest")
                HStack {
                    Button("Allow") { apply(rules + [request]) }
                    Button("Decline") { decline(request.id) }
                }
            }
        }
        Button("Add Tunnel…") { editor = EditorItem(original: nil) }
    }

    private func apply(_ updated: [ServiceTunnel]) {
        do { try change(updated); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

public struct GuestTunnelsView: View {
    let session: GuestHostSession
    @State private var adding = false

    public init(session: GuestHostSession) { self.session = session }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service Tunnels").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.tunnels.rules) { rule in TunnelRow(rule: rule, status: session.tunnels.status[rule.id]) }
                    ForEach(session.tunnels.requests) { rule in TunnelRow(rule: rule, status: "Awaiting host approval in VM Settings → Sharing") }
                    if session.tunnels.rules.isEmpty && session.tunnels.requests.isEmpty {
                        Text("No service tunnels configured.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Request Tunnel…") { adding = true }
                .disabled(!session.tunnels.available)
            if !session.tunnels.available {
                Text("Connect to a host that supports Service Tunnels.").font(.caption)
            }
        }
        .padding()
        .frame(width: 420, height: 240)
        .sheet(isPresented: $adding) {
            TunnelEditor(isGuest: true, rules: session.tunnels.rules + session.tunnels.requests) { try await session.requestTunnel($0) }
        }
    }
}

private struct TunnelRow: View {
    let rule: ServiceTunnel
    let status: String?
    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: rule.description).textSelection(.enabled)
            if let status = rule.isEnabled ? status : "Off" { Text(verbatim: status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct TunnelEditor: View {
    let isGuest: Bool
    let rules: [ServiceTunnel]
    let save: (ServiceTunnel) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hostListener = true
    @State private var listener = EndpointInput()
    @State private var destination = EndpointInput()
    @State private var saving = false
    @State private var error: String?

    let original: ServiceTunnel?

    init(isGuest: Bool, rules: [ServiceTunnel], original: ServiceTunnel? = nil, save: @escaping (ServiceTunnel) async throws -> Void) {
        self.isGuest = isGuest
        self.rules = rules
        self.original = original
        self.save = save
        if let original {
            _hostListener = State(initialValue: original.listensOnHost)
            _listener = State(initialValue: EndpointInput(original.listener))
            _destination = State(initialValue: EndpointInput(original.destination))
        }
    }

    private var rule: ServiceTunnel? {
        guard let source = listener.endpoint, let target = destination.endpoint else { return nil }
        var rule = ServiceTunnel(listensOnHost: hostListener, listener: source, destination: target)
        rule.isEnabled = original?.isEnabled ?? true
        return rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isGuest ? "Request Service Tunnel" : (original == nil ? "Add Service Tunnel" : "Edit Service Tunnel")).font(.headline)
            Picker("Listen on", selection: $hostListener) {
                Text("Host Mac").tag(true)
                Text("Guest VM").tag(false)
            }.pickerStyle(.segmented)
            TunnelEndpointField(title: "Listener", input: $listener)
            if listener.kind == .unix {
                Text("Use an unused path in a directory you own. Only your account should have write access to that directory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TunnelEndpointField(title: hostListener ? "Connect to on Guest VM" : "Connect to on Host Mac", input: $destination)
            if let rule, !rule.canAdd(to: rules) {
                Text("Choose an unused listener. Each VM supports up to 32 mappings.").font(.caption)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isGuest ? "Send Request" : (original == nil ? "Add" : "Save")) {
                    guard let rule, !saving else { return }
                    saving = true
                    Task {
                        do { try await save(rule); dismiss() }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule?.canAdd(to: rules) != true)
            }
        }
        .disabled(saving)
        .padding()
        .frame(width: 410)
    }
}

private struct EndpointInput {
    enum Kind { case ipv4, ipv6, unix }
    var kind = Kind.ipv4
    var value = ""
    init() {}

    init(_ endpoint: TunnelEndpoint) {
        switch endpoint {
        case .tcp(let port): kind = .ipv4; value = String(port)
        case .tcp6(let port): kind = .ipv6; value = String(port)
        case .unix(let path): kind = .unix; value = path
        }
    }

    var endpoint: TunnelEndpoint? {
        let result: TunnelEndpoint?
        switch kind {
        case .unix: result = .unix(value)
        case .ipv4: result = UInt16(value).map(TunnelEndpoint.tcp)
        case .ipv6: result = UInt16(value).map(TunnelEndpoint.tcp6)
        }
        return result?.isValid == true ? result : nil
    }
}

private struct TunnelEndpointField: View {
    let title: String
    @Binding var input: EndpointInput
    var body: some View {
        VStack(alignment: .leading) {
            Picker(title, selection: $input.kind) {
                Text("TCP · 127.0.0.1").tag(EndpointInput.Kind.ipv4)
                Text("TCP · ::1").tag(EndpointInput.Kind.ipv6)
                Text("Unix socket").tag(EndpointInput.Kind.unix)
            }
            TextField(input.kind == .unix ? "Absolute socket path" : "Port (1–65535)", text: $input.value)
        }
    }
}
