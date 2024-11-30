#if DEBUG
import SwiftUI
@_spi(GuestDebug) import VirtualCore

public struct GuestServicesDebugScreen: View {
    private let services: HostAppServices?
    private let instance: VMInstance?

    public init(services: HostAppServices) {
        self.services = services
        self.instance = nil
    }

    public init(instance: VMInstance) {
        self.services = try? instance.services
        self.instance = instance
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if let services {
                    GuestServicesDebugControls(services: services)
                } else if let instance {
                    GuestServicesDebugBootstrapView(instance: instance)
                } else {
                    Text("WAT").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("Guest Services Debug"))
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }
}

private struct GuestServicesDebugBootstrapView: View {
    @ObservedObject var instance: VMInstance
    @State private var services: HostAppServices?
    @State private var bootstrapTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if instance.isRunning {
                if let services {
                    GuestServicesDebugControls(services: services)
                } else {
                    Button("Bootstrap Services") {
                        bootstrapServices()
                    }
                    .disabled(bootstrapTask != nil)
                }
            } else {
                Text("Instance not running")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bootstrapServices() {
        bootstrapTask = Task {
            defer { bootstrapTask = nil }

            do {
                services = try instance.bootstrapGuestServiceClients()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

private struct GuestServicesDebugControls: View {
    @StateObject private var services: HostAppServices

    public init(services: HostAppServices) {
        self._services = .init(wrappedValue: services)
    }

    @State private var pingTask: Task<Void, Never>?
    @State private var pong: VMPongPayload?

    public var body: some View {
        Form {
            Button("Activate Services") {
                activateServices()
            }
            .disabled(services.hasConnection)

            Section("Ping") {
                Button {
                    sendPing()
                } label: {
                    Text("Send Ping")
                }
                .disabled(pingTask != nil)

                if let pong {
                    LabeledContent("Pong", value: pong.id)
                }
            }
            .disabled(!services.hasConnection)
        }
        .formStyle(.grouped)
        .monospacedDigit()
        .textSelection(.enabled)
    }

    private func activateServices() {
        Task {
            do {
                try await launchGuestIfNeeded()
                services.activate()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func sendPing() {
        pingTask = Task {
            defer { pingTask = nil }

            do {
                print("Send ping...")
                let reply = try await services.ping.sendPing()
                print("Pong: \(reply)")
                self.pong = reply
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func launchGuestIfNeeded() async throws {
        let url = try URL.embeddedGuestAppURL

        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            throw "Failed to retrieve guest app bundle ID."
        }

        if let instance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, !instance.isTerminated {
            print("Guest app already running.")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.environment = ["GUEST_SIMULATION_ENABLED": "1"]
        try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        try await Task.detached {
            try await Task.sleep(for: .seconds(2))
        }.value
    }
}

extension NSWorkspace.OpenConfiguration: @retroactive @unchecked Sendable { }

#endif // DEBUG
