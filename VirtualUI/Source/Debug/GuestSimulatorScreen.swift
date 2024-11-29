#if DEBUG
import SwiftUI
import VirtualCore

public struct GuestSimulatorScreen: View {
    let services = HostAppServices.guestSimulator

    public init() {

    }

    @State private var activated = false

    @State private var pingTask: Task<Void, Never>?
    @State private var pong: VMPongPayload?

    public var body: some View {
        NavigationStack {
            Form {
                Button("Activate Services") {
                    activateServices()
                }
                .disabled(activated)

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
                .disabled(!activated)
            }
            .formStyle(.grouped)
            .monospacedDigit()
            .textSelection(.enabled)
            .navigationTitle(Text("Guest Simulator"))
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    private func activateServices() {
        Task {
            do {
                try await launchGuestIfNeeded()
                services.activate()
                activated = true
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
        config.arguments = [
            "-GuestSimulationEnabled=YES"
        ]
        try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

extension NSWorkspace.OpenConfiguration: @retroactive @unchecked Sendable { }

#endif // DEBUG
