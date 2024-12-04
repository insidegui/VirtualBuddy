#if DEBUG
import SwiftUI
@_spi(GuestDebug) import VirtualCore
import Combine

@MainActor
private final class GuestServicesDebugController: ObservableObject {
    @Published private(set) var services: HostAppServices? {
        didSet {
            if services != nil { canDestroyInstance = true }
        }
    }
    @Published var canDestroyInstance = false

    func createInstance() {
        assert(services == nil)

        services = HostAppServices(coordinator: .current)
    }

    func destroyInstance() {
        assert(canDestroyInstance)
        assert(services != nil)

        services = nil
        canDestroyInstance = false
    }
}

public struct GuestServicesDebugScreen: View {
    private let instance: VMInstance?

    public init() {
        self.instance = nil
    }

    public init(instance: VMInstance) {
        self.instance = instance
    }

    @StateObject
    private var controller = GuestServicesDebugController()

    public var body: some View {
        NavigationStack {
            ZStack {
                if let services = controller.services {
                    GuestServicesDebugControls(services: services)
                } else if let instance {
                    GuestServicesDebugBootstrapView(instance: instance)
                } else {
                    servicesControlView
                        .task { controller.canDestroyInstance = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("Guest Services Debug"))
            .toolbar {
                if UserDefaults.isGuestSimulationEnabled, controller.canDestroyInstance {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            controller.destroyInstance()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Destroy instance")
                    }
                }
            }
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    private var servicesControlView: some View {
        /// We want to create the `HostAppServices` instance only when requested
        /// so that its lifecycle can mimick what happens in real usage, where the `VMInstance`
        /// owns `HostAppServices` and releases it when the VM is gone.
        Button("Create Instance") {
            controller.createInstance()
        }
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

    public var body: some View {
        Form {
            Button("Activate Services") {
                activateServices()
            }
            .disabled(services.hasConnection)

            PingServiceDebugControls(services: services)

            NotificationCenterServiceDebugControls(services: services)
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

    private func launchGuestIfNeeded() async throws {
        guard UserDefaults.isGuestSimulationEnabled else { return }
        
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

// MARK: - Ping

private struct PingServiceDebugControls: View {
    @ObservedObject var services: HostAppServices

    @State private var pingTask: Task<Void, Never>?
    @State private var pong: VMPongPayload?

    var body: some View {
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
}

// MARK: - Notification Center

private struct NotificationCenterServiceDebugControls: View {
    @ObservedObject var services: HostAppServices

    var body: some View {
        Section("Notification Center") {
            Button {
                subscribe()
            } label: {
                Text("Subscribe")
            }
        }
        .disabled(!services.hasConnection)
    }

    private func subscribe() {
        Task {
            do {
                try await services.notificationCenter.addObserver(for: "codes.rambo.test", type: .notify) { name in
                    print("-> Received: \(name)")
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

extension NSWorkspace.OpenConfiguration: @retroactive @unchecked Sendable { }

#endif // DEBUG
