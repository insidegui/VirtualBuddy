import AppKit
import AppStoreConnectDevices
import MacDebugHost
import SwiftUI
import UniformTypeIdentifiers
import VirtualCore

@MainActor
public final class XcodeProvisioningController: DebugProvisioningInteraction {
    public static let shared = XcodeProvisioningController()
    let keys = DeviceRegistrationKeys(service: (Bundle.main.bundleIdentifier ?? "codes.rambo.VirtualBuddy") + ".device-registration")
    public var provisioning: DebugProvisioning {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DebugProvisioning(cacheDirectory: support.appendingPathComponent("codes.rambo.VirtualBuddy/DevelopmentProfiles"), interaction: self)
    }
    private var panels: [UUID: ProvisioningPanel] = [:]

    private func panel(for destination: UUID) -> ProvisioningPanel {
        if let existing = panels[destination] { return existing }
        let name = VirtualMachineSessionUIManager.shared.sessions.values.first { $0.virtualMachine.uuid == destination }?.virtualMachine.name ?? "Virtual Mac"
        let panel = ProvisioningPanel(name: name, keys: keys)
        panels[destination] = panel
        panel.window.present(for: destination)
        return panel
    }

    public func showProgress(destination: UUID, detail: String, cancel: @escaping @MainActor () -> Void) {
        let panel = panel(for: destination)
        panel.message = detail
        panel.cancelRun = cancel
    }

    public func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction {
        try VBSettings.current.requireDeveloperFeatures()
        try Task.checkCancellation()
        return try await panel(for: request.destination).resolve(request)
    }

    public func dismiss(destination: UUID) {
        panels.removeValue(forKey: destination)?.dismiss()
    }
}

@MainActor
private final class ProvisioningPanel: ObservableObject {
    enum Registration { case checking, manual, available, registered, disabled }

    let window = XcodeRunPanel(title: "Xcode App Provisioning")
    let name: String
    let keys: DeviceRegistrationKeys
    @Published var message = "Preparing development profiles…"
    @Published var request: DebugProvisioningRequest?
    @Published var registration = Registration.checking
    @Published var issue: String?
    @Published var submitting = false
    var cancelRun: (@MainActor () -> Void)?
    private var continuation: CheckedContinuation<DebugProvisioningAction, Error>?
    private var operation: Task<Void, Never>?

    init(name: String, keys: DeviceRegistrationKeys) {
        self.name = name
        self.keys = keys
        window.host(ProvisioningView(panel: self))
    }

    func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.request = request
                checkRegistration()
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }

    func checkRegistration() {
        guard let request else { return }
        operation?.cancel()
        registration = .checking
        issue = request.detail
        operation = Task {
            do {
                let configured = try await keys.teams().contains(request.teamID)
                try Task.checkCancellation()
                guard configured else { registration = .manual; return }
                let status = try await MacDeviceRegistration(keys: keys).lookup(udid: request.udid, teamID: request.teamID)
                try Task.checkCancellation()
                switch status {
                case .enabled: registration = .registered
                case .disabled: registration = .disabled
                case nil: registration = .available
                }
            } catch where !Task.isCancelled {
                registration = .manual
                issue = error.localizedDescription
            } catch {}
        }
    }

    func register() {
        guard let request, registration == .available, !submitting else { return }
        submitting = true
        operation = Task {
            defer { submitting = false }
            do {
                try VBSettings.current.requireDeveloperFeatures()
                let status = try await MacDeviceRegistration(keys: keys).register(name: name, udid: request.udid, teamID: request.teamID)
                try Task.checkCancellation()
                if status == .enabled { finish(.success(.retry)) } else { registration = .disabled }
            } catch where !Task.isCancelled { issue = error.localizedDescription } catch {}
        }
    }

    func chooseProfiles() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = ["provisionprofile", "mobileprovision"].compactMap { UTType(filenameExtension: $0) }
        picker.allowsMultipleSelection = true
        picker.message = "Choose development profiles for this app and its extensions."
        picker.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.finish(.success(.importProfiles(picker.urls)))
        }
    }

    func finish(_ result: Result<DebugProvisioningAction, Error>) {
        operation?.cancel()
        operation = nil
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(with: result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
        cancelRun?()
    }

    func dismiss() {
        finish(.failure(CancellationError()))
        cancelRun = nil
        window.dismiss()
    }
}

private struct ProvisioningView: View {
    @ObservedObject var panel: ProvisioningPanel
    @State private var confirmingRegistration = false
    @State private var editingKey = false

    var body: some View {
        XcodeRunSheet(title: panel.request == nil ? "Preparing App for Debugging" : "Provision App for Debugging",
                      subtitle: panel.request == nil ? "Xcode will launch your app on “\(panel.name)” when signing finishes."
                          : "To run your app on “\(panel.name)”, its development profile must include this Mac.") {
            if let request = panel.request {
                XcodeRunRow(symbol: "person.2", title: "Signing Team \(request.teamID)") {
                    Text(request.bundleIDs.joined(separator: "\n")).textSelection(.enabled)
                }
                XcodeRunRow(symbol: "desktopcomputer", title: "Provisioning UDID") {
                    HStack(spacing: 8) {
                        Text(request.udid).font(.callout.monospaced()).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(request.udid, forType: .string)
                        } label: {
                            Label("Copy Provisioning UDID", systemImage: "doc.on.doc").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Provisioning UDID")
                    }
                }
                XcodeRunRow(symbol: "person.text.rectangle", title: "Device Registration") {
                    registrationStatus
                    if !request.automaticSigning {
                        Text("Import development profiles for the listed apps and extensions, or check for profiles already installed on this Mac.")
                    }
                }
                if let issue = panel.issue {
                    XcodeRunRow(symbol: "exclamationmark.triangle", title: "Provisioning Details") {
                        Text(issue).textSelection(.enabled)
                    }
                }
            } else {
                XcodeRunRow(symbol: "signature", title: "Development Profiles") {
                    Text(panel.message)
                    ProgressView().progressViewStyle(.linear).accessibilityLabel(panel.message)
                }
            }
        } actions: {
            if let request = panel.request {
                Menu("Other Options") {
                    if panel.registration == .manual {
                        Button("Add Team API Key…") { editingKey = true }
                    }
                    if panel.registration == .available {
                        Link("Register in Apple Developer", destination: Self.registerDeviceURL)
                    }
                    if request.automaticSigning || panel.registration == .available {
                        Button("Import Profiles…") { panel.chooseProfiles() }
                    }
                    if !request.automaticSigning || panel.registration == .available {
                        Button(request.automaticSigning ? "Refresh Profiles" : "Check Profiles") { panel.finish(.success(.retry)) }
                    }
                }
                .disabled(panel.submitting)
            }
            Spacer()
            Button("Cancel", role: .cancel) { panel.cancel() }
                .keyboardShortcut(.cancelAction)
                .airGlassButtonStyle()
            if let request = panel.request {
                if panel.registration == .available {
                    Button("Register This Mac…") { confirmingRegistration = true }
                        .keyboardShortcut(.defaultAction)
                        .airGlassButtonStyle(prominent: true)
                        .disabled(panel.submitting)
                        .confirmationDialog("Register \(panel.name) on team \(request.teamID)?", isPresented: $confirmingRegistration) {
                            Button("Register Mac") { panel.register() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Registration uses one of this team’s Mac device slots for the membership year.")
                        }
                } else {
                    Button(request.automaticSigning ? "Refresh Profiles" : "Import Profiles…") {
                        if request.automaticSigning { panel.finish(.success(.retry)) } else { panel.chooseProfiles() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .airGlassButtonStyle(prominent: true)
                }
            }
        }
        .sheet(isPresented: $editingKey, onDismiss: panel.checkRegistration) {
            if let request = panel.request { RegistrationKeyEditor(keys: panel.keys, signingTeam: request.teamID) }
        }
    }

    private static let registerDeviceURL = URL(string: "https://developer.apple.com/account/resources/devices/add")!

    @ViewBuilder private var registrationStatus: some View {
        if panel.registration == .checking || panel.submitting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(panel.submitting ? "Registering this Mac…" : "Checking with App Store Connect…")
            }
        } else {
            switch panel.registration {
            case .manual:
                Text("Register this Mac with your team, then refresh its profiles. You can also add a team API key in Other Options.")
            case .available:
                Text("This Mac can be registered with your team using its App Store Connect key.")
            case .registered:
                Text("This Mac is registered. It may take time for new profiles to include it.")
            case .disabled:
                Text("This Mac is disabled on the signing team. Ask a team administrator to review it.")
            case .checking: EmptyView()
            }
            if panel.registration == .registered || panel.registration == .disabled {
                Link("View Registered Devices", destination: URL(string: "https://developer.apple.com/account/resources/devices/list")!)
                    .foregroundStyle(.tint)
            } else if panel.registration == .manual {
                Link("Register in Apple Developer", destination: Self.registerDeviceURL)
                    .foregroundStyle(.tint)
            }
        }
    }
}
