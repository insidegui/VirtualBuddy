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
    /// Preparing an app that is already provisioned for the virtual machine usually takes less
    /// than this. Waiting keeps a panel the developer cannot act on from flashing on screen.
    var progressDelay = Duration.seconds(1.5)

    private func panel(for destination: UUID) -> ProvisioningPanel {
        if let existing = panels[destination] { return existing }
        let name = VirtualMachineSessionUIManager.shared.sessions.values.first { $0.virtualMachine.uuid == destination }?.virtualMachine.name ?? "Virtual Machine"
        let panel = ProvisioningPanel(name: name, keys: keys, destination: destination)
        panels[destination] = panel
        return panel
    }

    public func showProgress(destination: UUID, detail: String, cancel: @escaping @MainActor () -> Void) {
        let panel = panel(for: destination)
        panel.message = detail
        panel.cancelRun = cancel
        panel.present(after: progressDelay)
    }

    public func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction {
        try VBSettings.current.requireDeveloperFeatures()
        try Task.checkCancellation()
        let panel = panel(for: request.destination)
        // The Run waits for the developer here, so ask for their attention right away.
        panel.present()
        return try await panel.resolve(request)
    }

    public func dismiss(destination: UUID) {
        panels.removeValue(forKey: destination)?.dismiss()
    }
}

@MainActor
private final class ProvisioningPanel: ObservableObject {
    enum Registration { case checking, manual, unchecked, available, registered, disabled }

    let window = XcodeRunPanel(title: "Xcode App Provisioning")
    let name: String
    let keys: DeviceRegistrationKeys
    private let destination: UUID
    private var presentation: Task<Void, Never>?
    private var isPresented = false
    @Published var message = "Preparing development profiles…"
    @Published var request: DebugProvisioningRequest?
    @Published var registration = Registration.checking
    @Published var issue: String?
    @Published var submitting = false
    var cancelRun: (@MainActor () -> Void)?
    private var continuation: CheckedContinuation<DebugProvisioningAction, Error>?
    private var operation: Task<Void, Never>?
    /// One value for this panel, so the developer confirms their presence once per Run.
    private lazy var api = MacDeviceRegistration(keys: keys)
    /// The team key is used only after the developer asks to check the virtual machine's registration.
    private var checksApproved = false

    init(name: String, keys: DeviceRegistrationKeys, destination: UUID) {
        self.name = name
        self.keys = keys
        self.destination = destination
        window.host(ProvisioningView(panel: self))
    }

    /// Shows the panel now. A delay already under way is not extended by later progress.
    func present() {
        presentation?.cancel()
        presentation = nil
        guard !isPresented else { return }
        isPresented = true
        window.present(for: destination)
    }

    func present(after delay: Duration) {
        guard !isPresented, presentation == nil else { return }
        presentation = Task {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            present()
        }
    }

    func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.request = request
                refreshRegistration()
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }

    func checkRegistration() {
        guard request != nil, registration == .unchecked else { return }
        checksApproved = true
        refreshRegistration()
    }

    func refreshRegistration() {
        guard let request else { return }
        operation?.cancel()
        registration = .checking
        issue = request.detail
        operation = Task {
            do {
                let configured = try await keys.teams().contains(request.teamID)
                try Task.checkCancellation()
                guard configured else { registration = .manual; return }
                guard checksApproved else { registration = .unchecked; return }
                try VBSettings.current.requireDeveloperFeatures()
                let status = try await api.lookup(udid: request.udid, teamID: request.teamID)
                try Task.checkCancellation()
                switch status {
                case .enabled: registration = .registered
                case .disabled: registration = .disabled
                case nil: registration = .available
                }
            } catch is CancellationError {
                // The developer declined to confirm their presence. Ask again before the next use.
                guard !Task.isCancelled else { return }
                checksApproved = false
                registration = .unchecked
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
                let status = try await api.register(name: name, udid: request.udid, teamID: request.teamID)
                try Task.checkCancellation()
                if status == .enabled { finish(.success(.retry)) } else { registration = .disabled }
            } catch is CancellationError {} catch where !Task.isCancelled { issue = error.localizedDescription } catch {}
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
        presentation?.cancel()
        presentation = nil
        finish(.failure(CancellationError()))
        cancelRun = nil
        window.dismiss()
    }
}

private struct ProvisioningView: View {
    @ObservedObject var panel: ProvisioningPanel
    var body: some View {
        ProvisioningForm(name: panel.name, message: panel.message,
                         request: panel.request.map {
                             .init(teamID: $0.teamID, udid: $0.udid, bundleIDs: $0.bundleIDs, automaticSigning: $0.automaticSigning)
                         },
                         registration: panel.registration, issue: panel.issue, submitting: panel.submitting, keys: panel.keys) { action in
            switch action {
            case .chooseProfiles: panel.chooseProfiles()
            case .retry: panel.finish(.success(.retry))
            case .cancel: panel.cancel()
            case .register: panel.register()
            case .checkRegistration: panel.checkRegistration()
            case .refreshRegistration: panel.refreshRegistration()
            }
        }
    }
}

private struct ProvisioningForm: View {
    struct Request {
        let teamID: String
        let udid: String
        let bundleIDs: [String]
        let automaticSigning: Bool
    }

    enum Action { case chooseProfiles, retry, cancel, register, checkRegistration, refreshRegistration }

    let name: String
    let message: String
    let request: Request?
    let registration: ProvisioningPanel.Registration
    let issue: String?
    let submitting: Bool
    let keys: any RegistrationKeyStore
    let perform: (Action) -> Void

    @State private var confirmingRegistration = false
    @State private var editingKey = false

    var body: some View {
        XcodeRunSheet(title: request == nil ? "Preparing App for Debugging" : "Provision App for Debugging",
                      subtitle: request == nil ? "Xcode will launch your app in “\(name)” when signing finishes."
                          : "To run your app in “\(name)”, its development profile must include the virtual machine’s provisioning UDID.") {
            if let request {
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
                        Text("Import development profiles for the listed apps and extensions, or check for profiles already installed on the host Mac.")
                    }
                }
                if let issue {
                    XcodeRunRow(symbol: "exclamationmark.triangle", title: "Provisioning Details") {
                        Text(issue).textSelection(.enabled)
                    }
                }
            } else {
                XcodeRunRow(symbol: "signature", title: "Development Profiles") {
                    Text(message)
                    ProgressView().progressViewStyle(.linear).accessibilityLabel(message)
                }
            }
        } actions: {
            if let request {
                let offersRegistration = registration == .available || registration == .unchecked
                Menu("Other Options") {
                    if registration == .manual {
                        Button("Add Team API Key…") { editingKey = true }
                    }
                    if registration == .available {
                        Link("Register in Apple Developer", destination: Self.registerDeviceURL)
                    }
                    if request.automaticSigning || offersRegistration {
                        Button("Import Profiles…") { perform(.chooseProfiles) }
                    }
                    if !request.automaticSigning || offersRegistration {
                        Button(request.automaticSigning ? "Refresh Profiles" : "Check Profiles") { perform(.retry) }
                    }
                }
                .disabled(submitting)
            }
            Spacer()
            Button("Cancel", role: .cancel) { perform(.cancel) }
                .keyboardShortcut(.cancelAction)
                .airGlassButtonStyle()
            if let request {
                if registration == .available {
                    Button("Register Virtual Machine…") { confirmingRegistration = true }
                        .keyboardShortcut(.defaultAction)
                        .airGlassButtonStyle(prominent: true)
                        .disabled(submitting)
                        .confirmationDialog("Register “\(name)” with team \(request.teamID)?", isPresented: $confirmingRegistration) {
                            Button("Register Virtual Machine") { perform(.register) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Registration uses one of this team’s Mac device slots for the membership year.")
                        }
                } else if registration == .unchecked {
                    Button("Check Registration") { perform(.checkRegistration) }
                        .keyboardShortcut(.defaultAction)
                        .airGlassButtonStyle(prominent: true)
                } else {
                    Button(request.automaticSigning ? "Refresh Profiles" : "Import Profiles…") {
                        if request.automaticSigning { perform(.retry) } else { perform(.chooseProfiles) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .airGlassButtonStyle(prominent: true)
                }
            }
        }
        .sheet(isPresented: $editingKey, onDismiss: { perform(.refreshRegistration) }) {
            if let request { RegistrationKeyEditor(keys: keys, signingTeam: request.teamID) }
        }
    }

    private static let registerDeviceURL = URL(string: "https://developer.apple.com/account/resources/devices/add")!

    @ViewBuilder private var registrationStatus: some View {
        if registration == .checking || submitting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(submitting ? "Registering the virtual machine…" : "Checking with App Store Connect…")
            }
        } else {
            switch registration {
            case .manual:
                Text("Register the virtual machine with your team, then refresh the development profiles. You can also add a team API key in Other Options.")
            case .unchecked:
                Text("Check whether the virtual machine is registered with your signing team. VirtualBuddy asks for Touch ID or your password before using the team’s saved API key.")
            case .available:
                Text("Use your team’s App Store Connect key to register the virtual machine.")
            case .registered:
                Text("The virtual machine is registered. It may take time for new profiles to include it.")
            case .disabled:
                Text("Registration for this virtual machine is disabled. Ask a signing team administrator to review it.")
            case .checking: EmptyView()
            }
            if registration == .registered || registration == .disabled {
                Link("View Registered Devices", destination: URL(string: "https://developer.apple.com/account/resources/devices/list")!)
                    .foregroundStyle(.tint)
            } else if registration == .manual {
                Link("Register in Apple Developer", destination: Self.registerDeviceURL)
                    .foregroundStyle(.tint)
            }
        }
    }
}

#if DEBUG
private extension ProvisioningForm {
    static func preview(registration: ProvisioningPanel.Registration? = nil, automaticSigning: Bool = true,
                        issue: String? = nil, submitting: Bool = false) -> Self {
        let request = registration.map { _ in
            Request(teamID: "EXAMPLE123", udid: "0123456789abcdef0123456789abcdef01234567",
                    bundleIDs: ["com.example.FieldNotes", "com.example.FieldNotes.Share"], automaticSigning: automaticSigning)
        }
        return Self(name: "Test Mac", message: "Refreshing development profiles with Xcode…", request: request,
                    registration: registration ?? .checking, issue: issue, submitting: submitting, keys: PreviewRegistrationKeys()) { _ in }
    }
}

#Preview("Refreshing Development Profiles") {
    ProvisioningForm.preview()
}

#Preview("Manual Provisioning") {
    ProvisioningForm.preview(registration: .manual, automaticSigning: false)
}

#Preview("Check Registration") {
    ProvisioningForm.preview(registration: .unchecked)
}

#Preview("Checking Registration") {
    ProvisioningForm.preview(registration: .checking)
}

#Preview("Register Virtual Machine") {
    ProvisioningForm.preview(registration: .available)
}

#Preview("Registering Virtual Machine") {
    ProvisioningForm.preview(registration: .available, submitting: true)
}

#Preview("Registered Virtual Machine") {
    ProvisioningForm.preview(registration: .registered)
}

#Preview("Registration Issue") {
    ProvisioningForm.preview(registration: .disabled, issue: "The development profile for the share extension does not include the virtual machine’s provisioning UDID.")
}
#endif
