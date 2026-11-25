import SwiftUI
import VirtualWormhole

/// Sheet for creating or editing a service tunnel on the host, or requesting a new one from the guest.
struct ServiceTunnelEditor: View {
    enum Mode {
        /// Host is adding a new tunnel.
        case add
        /// Host is editing an existing tunnel.
        case edit(ServiceTunnel)
        /// Guest is requesting a new tunnel, which the host must approve.
        case request

        var title: String {
            switch self {
            case .add: "Add Service Tunnel"
            case .edit: "Edit Service Tunnel"
            case .request: "Request Service Tunnel"
            }
        }

        var confirmationTitle: String {
            switch self {
            case .add: "Add"
            case .edit: "Save"
            case .request: "Send Request"
            }
        }

        var original: ServiceTunnel? {
            guard case .edit(let tunnel) = self else { return nil }
            return tunnel
        }
    }

    let mode: Mode
    /// Other tunnels that already exist, used for validating that the listener is not already in use.
    let existingTunnels: [ServiceTunnel]
    let save: (ServiceTunnel) async throws -> Void

    @State private var listensOnHost = true
    @State private var listener = TunnelEndpointInput()
    @State private var destination = TunnelEndpointInput()
    @State private var isSaving = false
    @State private var errorMessage: String?

    @Environment(\.dismiss)
    private var dismiss

    init(mode: Mode, existingTunnels: [ServiceTunnel], save: @escaping (ServiceTunnel) async throws -> Void) {
        self.mode = mode
        self.existingTunnels = existingTunnels
        self.save = save

        if let original = mode.original {
            self._listensOnHost = State(initialValue: original.listensOnHost)
            self._listener = State(initialValue: TunnelEndpointInput(original.listener))
            self._destination = State(initialValue: TunnelEndpointInput(original.destination))
        }
    }

    private var tunnel: ServiceTunnel? {
        guard let listener = listener.endpoint, let destination = destination.endpoint else { return nil }
        var tunnel = ServiceTunnel(listensOnHost: listensOnHost, listener: listener, destination: destination)
        tunnel.isEnabled = mode.original?.isEnabled ?? true
        return tunnel
    }

    private var canSave: Bool { tunnel?.canAdd(to: existingTunnels) == true }

    private var conflictMessage: String? {
        guard let tunnel, !tunnel.canAdd(to: existingTunnels) else { return nil }

        return if existingTunnels.count >= ServiceTunnel.maximumCount {
            "Each virtual machine supports up to \(ServiceTunnel.maximumCount) service tunnels."
        } else {
            "Another tunnel is already listening on this address on the \(tunnel.listenerSideName)."
        }
    }

    private var listenerSideName: String { listensOnHost ? "Host" : "Guest" }
    private var destinationSideName: String { listensOnHost ? "Guest" : "Host" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Listen On", selection: $listensOnHost) {
                        Text("Host").tag(true)
                        Text("Guest").tag(false)
                    }
                    .pickerStyle(.segmented)

                    TunnelEndpointFields(input: $listener)
                } header: {
                    Text("Listener")
                } footer: {
                    if listener.kind == .unix {
                        Text("Use an unused path in a directory you own. Only your account should have write access to that directory.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("Connect to \(destinationSideName)") {
                    TunnelEndpointFields(input: $destination)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if let conflictMessage {
                    Text(conflictMessage)
                        .foregroundStyle(.yellow)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmationTitle, action: performSave)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave || isSaving)
                }
            }
            .disabled(isSaving)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func performSave() {
        guard let tunnel, canSave, !isSaving else { return }

        isSaving = true

        Task {
            do {
                try await save(tunnel)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}

private extension ServiceTunnel {
    static let maximumCount = 32
}

private struct TunnelEndpointInput {
    enum Kind: Hashable {
        case ipv4
        case ipv6
        case unix
    }

    var kind = Kind.ipv4
    var value = ""

    init() { }

    init(_ endpoint: TunnelEndpoint) {
        switch endpoint {
        case .tcp(let port):
            kind = .ipv4
            value = String(port)
        case .tcp6(let port):
            kind = .ipv6
            value = String(port)
        case .unix(let path):
            kind = .unix
            value = path
        }
    }

    var endpoint: TunnelEndpoint? {
        let result: TunnelEndpoint? = switch kind {
        case .unix: .unix(value)
        case .ipv4: UInt16(value).map(TunnelEndpoint.tcp)
        case .ipv6: UInt16(value).map(TunnelEndpoint.tcp6)
        }

        return result?.isValid == true ? result : nil
    }
}

private struct TunnelEndpointFields: View {
    @Binding var input: TunnelEndpointInput

    var body: some View {
        Picker("Socket", selection: $input.kind) {
            Text("TCP · 127.0.0.1").tag(TunnelEndpointInput.Kind.ipv4)
            Text("TCP · ::1").tag(TunnelEndpointInput.Kind.ipv6)
            Text("Unix Socket").tag(TunnelEndpointInput.Kind.unix)
        }
        .onChange(of: input.kind) { oldValue, newValue in
            /// A port number is never a valid socket path and vice-versa.
            guard (oldValue == .unix) != (newValue == .unix) else { return }
            input.value = ""
        }

        LabeledContent(input.kind == .unix ? "Path" : "Port") {
            TextField(
                input.kind == .unix ? "Path" : "Port",
                text: $input.value,
                prompt: Text(verbatim: input.kind == .unix ? "/path/to/service.sock" : "1–65535")
            )
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .monospacedDigit()
        }
    }
}

#if DEBUG
#Preview("Add") {
    ServiceTunnelEditor(mode: .add, existingTunnels: []) { _ in }
}

#Preview("Edit — Unix Socket") {
    ServiceTunnelEditor(mode: .edit(.previewUnixSocket), existingTunnels: []) { _ in }
}

#Preview("Edit — Conflict") {
    ServiceTunnelEditor(mode: .edit(.previewWebServer), existingTunnels: [.previewWebServer]) { _ in }
}

#Preview("Guest Request") {
    ServiceTunnelEditor(mode: .request, existingTunnels: []) { _ in }
}
#endif
