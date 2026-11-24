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
        XcodeDebugSetup.present(panel.window, for: destination)
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
private final class ProvisioningPanel: NSObject, ObservableObject, NSWindowDelegate {
    enum Registration { case checking, manual, available, registered, disabled }

    let window: NSPanel
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
        window = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Xcode App Provisioning"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let view = NSHostingController(rootView: ProvisioningView(panel: self))
        view.sizingOptions = [.preferredContentSize]
        window.contentViewController = view
        window.setContentSize(view.view.fittingSize)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }

    func dismiss() {
        finish(.failure(CancellationError()))
        cancelRun = nil
        window.parent?.removeChildWindow(window)
        window.close()
        window.contentViewController = nil
    }
}

private struct ProvisioningView: View {
    @ObservedObject var panel: ProvisioningPanel
    @State private var confirmingRegistration = false
    @State private var editingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(panel.name).font(.headline)
            if let request = panel.request {
                Text("Team \(request.teamID) needs a development profile for \(request.bundleIDs.joined(separator: ", ")).")
                    .textSelection(.enabled)
                LabeledContent("Provisioning UDID") {
                    Text(request.udid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(request.udid, forType: .string)
                    }
                }
                if let issue = panel.issue { Text(issue).foregroundStyle(.secondary).textSelection(.enabled) }
                switch panel.registration {
                case .checking: ProgressView("Checking device registration…").controlSize(.small)
                case .manual:
                    Text("Register this Mac once per signing team in Apple Developer, or add a team API key to register it here.")
                    Button("Add Team API Key…") { editingKey = true }
                case .available:
                    Button("Register This Mac…") { confirmingRegistration = true }
                        .disabled(panel.submitting)
                        .confirmationDialog("Register \(panel.name) on team \(request.teamID)?", isPresented: $confirmingRegistration) {
                            Button("Register Mac") { panel.register() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Registration uses one of this team’s Mac device slots for the membership year.")
                        }
                case .registered: Text("Apple lists this Mac as registered. Newly registered devices can take time to become eligible for profiles.")
                case .disabled: Text("This Mac is disabled on the signing team. A team administrator can review it in Apple Developer.")
                }
                if !request.automaticSigning {
                    Text("This target uses manual signing. Import development profiles that include this Mac for the listed bundle identifiers.")
                }
                HStack {
                    if panel.registration == .registered || panel.registration == .disabled {
                        Link("View Registered Devices", destination: URL(string: "https://developer.apple.com/account/resources/devices/list")!)
                    } else {
                        Link("Register in Apple Developer", destination: URL(string: "https://developer.apple.com/account/resources/devices/add")!)
                    }
                    Spacer()
                    Button("Import Profiles…") { panel.chooseProfiles() }
                    Button(request.automaticSigning ? "Refresh Profiles" : "Check Profiles") { panel.finish(.success(.retry)) }
                }
                .disabled(panel.submitting)
            } else {
                ProgressView(panel.message).controlSize(.small)
            }
            Button("Cancel", role: .cancel) { panel.cancel() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 490, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            panel.window.setContentSize(size)
        }
        .sheet(isPresented: $editingKey, onDismiss: panel.checkRegistration) {
            if let request = panel.request { RegistrationKeyEditor(keys: panel.keys, signingTeam: request.teamID) }
        }
    }
}
