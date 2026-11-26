import SwiftUI
import VirtualCore
import BuddyUI
import DeepLinkSecurity
import LocalAuthentication
import ManagedPreferencesUI

struct SecuritySettingsView: View {
    let session: SecuritySettingsSession

    @EnvironmentObject private var sentinel: DeepLinkSentinel

    private var store: DeepLinkManagementStore { sentinel.managementStore }

    @State private var descriptors = [DeepLinkClientDescriptor]()
    @State private var levelAwaitingConfirmation: ServiceTunnelSecurityLevel?
    @State private var isConfirmingForget = false

    @ManagedValue(for: .serviceTunnelMinimumReviewLevel, schema: VirtualBuddyManagedPreferences.schema, default: "")
    private var managedMinimumLevel: String

    @ManagedValue(for: .disableCommandLineAccess, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var commandLineAccessDisabled: Bool

    var commandLineTool = CommandLineToolInstaller.current

    private var minimumLevel: ServiceTunnelSecurityLevel? {
        VirtualBuddyManagedPreferences.serviceTunnelMinimumReviewLevel($managedMinimumLevel)
    }

    /// The level in effect, which is what the user chose unless the organization requires more review.
    private var effectiveLevel: ServiceTunnelSecurityLevel {
        max(session.tunnelLevel, minimumLevel ?? .reviewNone)
    }

    var body: some View {
        SettingsPane {
            SettingsRow("Changes:") {
                Button {
                    session.isUnlocked ? session.lock() : unlock()
                } label: {
                    Label(session.isUnlocked ? "Lock" : "Unlock Settings", systemImage: session.isUnlocked ? "lock.open" : "lock")
                }
                SettingsCaption("Unlock with Touch ID or your password before making changes.")
            }

            SettingsDivider()

            SettingsRow("App access:") {
                SettingsItemList {
                    if descriptors.isEmpty {
                        Text("No apps have requested access.")
                            .settingsListItemTitle()
                    } else {
                        ForEach(descriptors) { descriptor in
                            Toggle(isOn: toggleBinding(for: descriptor)) {
                                HStack(spacing: 6) {
                                    Image(nsImage: descriptor.icon.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .accessibilityHidden(true)

                                    Text(descriptor.displayName)
                                        .settingsListItemTitle()
                                }
                            }
                        }
                    }
                }
                .disabled(!session.isUnlocked)
                SettingsCaption("VirtualBuddy asks the first time an app opens a deep link. Allowed apps aren't asked again.")
            }

            SettingsDivider()

            SettingsRow("Tunnel review:") {
                Picker("Tunnel review", selection: levelBinding) {
                    ForEach(ServiceTunnelSecurityLevel.allCases.reversed(), id: \.self) { level in
                        Text(level.title)
                            .selectionDisabled(level < (minimumLevel ?? .reviewNone))
                            .tag(level)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!session.isUnlocked)

                if let minimumLevel, minimumLevel > .reviewNone {
                    ManagedRestrictionBannerView(title: "Your organization requires service tunnels to be reviewed.")
                }

                SettingsCaption(effectiveLevel.explanation)

                if session.rememberedTunnelCount == nil {
                    SettingsCaption("VirtualBuddy can't read its security settings from the Keychain, so every change is reviewed.")
                } else if let count = session.rememberedTunnelCount, count > 0 || effectiveLevel == .reviewNew {
                    Button("Forget Reviewed Tunnels…") { isConfirmingForget = true }
                        .disabled(!session.isUnlocked || count == 0)
                        .settingsButtonBelowCaption()
                    SettingsCaption("^[\(count) tunnel](inflect: true) reviewed on this Mac.")
                }
            }

            SettingsDivider()

            SettingsRow("Command line:") {
                Toggle("Allow vbctl to control VirtualBuddy", isOn: commandLineAccessDisabled ? .constant(false) : commandLineAccessBinding)
                    .disabled(!session.isUnlocked || commandLineAccessDisabled)

                if commandLineAccessDisabled {
                    ManagedRestrictionBannerView(title: "Command-line access is disabled by your organization.")
                } else {
                    SettingsCaption("Anything running as you can use vbctl to control virtual machines. Tunnels it adds are still reviewed.")
                }

                if session.isCommandLineAccessEnabled && !commandLineAccessDisabled {
                    CommandLineToolSettings(installer: commandLineTool)
                }
            }
        }
        .task {
            for await descriptors in store.clientDescriptors() {
                self.descriptors = descriptors
            }
        }
        .onAppear { session.reload() }
        .alert(
            "Review Fewer Service Tunnels?",
            isPresented: Binding { levelAwaitingConfirmation != nil } set: { if !$0 { levelAwaitingConfirmation = nil } },
            presenting: levelAwaitingConfirmation
        ) { level in
            Button("Cancel", role: .cancel) { }
            Button(level.title, role: .destructive) { setLevel(level) }
        } message: { level in
            Text(level.explanation)
        }
        .alert("Forget Reviewed Tunnels?", isPresented: $isConfirmingForget) {
            Button("Cancel", role: .cancel) { }
            Button("Forget", role: .destructive) {
                perform { try session.forgetRememberedTunnels() }
            }
        } message: {
            Text("Tunnels that run because they were reviewed before stop until they're reviewed again, including in running virtual machines.")
        }
    }

    private var levelBinding: Binding<ServiceTunnelSecurityLevel> {
        Binding {
            effectiveLevel
        } set: { level in
            // Asking for more review takes effect right away. Asking for less is confirmed first.
            if level < effectiveLevel {
                levelAwaitingConfirmation = level
            } else {
                setLevel(level)
            }
        }
    }

    private var commandLineAccessBinding: Binding<Bool> {
        Binding {
            session.isCommandLineAccessEnabled
        } set: { enabled in
            perform { try session.setCommandLineAccessEnabled(enabled) }
        }
    }

    private func setLevel(_ level: ServiceTunnelSecurityLevel) {
        perform { try session.setTunnelLevel(level) }
    }

    private func unlock() {
        Task {
            do {
                try await session.unlock()
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
                // Nothing to report when the user changed their mind.
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() }
        catch { NSAlert(error: error).runModal() }
    }

    private func toggleBinding(for descriptor: DeepLinkClientDescriptor) -> Binding<Bool> {
        .init {
            descriptor.authorization == .authorized
        } set: { granted in
            Task { @MainActor in
                do {
                    try await sentinel.setAuthorization(granted ? .authorized : .denied, for: descriptor)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
}

/// Links the command-line tool into the user's `PATH`, which isn't a security setting and so doesn't need them unlocked.
private struct CommandLineToolSettings: View {
    let installer: CommandLineToolInstaller

    @State private var status = CommandLineToolInstaller.Status.notInstalled
    @State private var isInstalling = false
    @State private var manualCommand: String?

    var body: some View {
        Group {
            switch status {
            case .installed(let link):
                Button("Uninstall Command-Line Tool") {
                    installer.uninstall()
                    status = installer.status()
                }
                .settingsButtonBelowCaption()
                SettingsCaption("Installed at \((link.path as NSString).abbreviatingWithTildeInPath).")
            case .notInstalled:
                Button("Install Command-Line Tool…") { install() }
                    .disabled(isInstalling)
                    .settingsButtonBelowCaption()
                SettingsCaption("Links vbctl into a folder in your PATH.")
            }
        }
        .onAppear { status = installer.status() }
        .alert(
            "Install vbctl in Terminal",
            isPresented: Binding { manualCommand != nil } set: { if !$0 { manualCommand = nil } },
            presenting: manualCommand
        ) { command in
            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            Button("Cancel", role: .cancel) { }
        } message: { command in
            Text("None of the folders in your PATH can be changed without an administrator password. Run this command in Terminal to install vbctl:\n\n\(command)")
        }
    }

    private func install() {
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                try await installer.install()
            } catch let error as CommandLineToolInstaller.ManualInstallationRequired {
                manualCommand = error.command
            } catch {
                NSAlert(error: error).runModal()
            }
            status = installer.status()
        }
    }
}

private extension ServiceTunnelSecurityLevel {
    var title: LocalizedStringKey {
        switch self {
        case .reviewAll: "Every Change"
        case .reviewNew: "New Tunnels Only"
        case .reviewNone: "Never"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .reviewAll:
            "VirtualBuddy asks before a virtual machine adds a tunnel or uses one that wasn't approved for it on this Mac."
        case .reviewNew:
            "VirtualBuddy asks the first time a tunnel uses a port or socket on this Mac. After that, any virtual machine can use it."
        case .reviewNone:
            "Virtual machines can add tunnels to any port or socket on this Mac without asking. Only use this with virtual machines you trust."
        }
    }
}

/// Locks the security settings once nobody is looking at them anymore.
private struct SecuritySettingsLockModifier: ViewModifier {
    let session: SecuritySettingsSession

    func body(content: Content) -> some View {
        content
            .background(WindowCloseObserver { session.lock() })
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in session.lock() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in session.lock() }
    }
}

extension View {
    /// Locks the security settings when the window showing the view closes, the screen sleeps, or another user takes over the Mac.
    func locksSecuritySettingsWhenUnattended(_ session: SecuritySettingsSession) -> some View {
        modifier(SecuritySettingsLockModifier(session: session))
    }
}

/// Reports when the window the view is in closes. A settings window is kept around and shown again later,
/// so its views don't go away when it does.
private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onClose: @MainActor () -> Void = {}
        private var observation: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onClose() }
                }
            }
            // Leaving a window counts as that window going away.
            if window == nil { onClose() }
        }

        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
        }
    }
}

// MARK: - Preview

#if DEBUG
final class PreviewDeepLinkAuthUI: DeepLinkAuthUI {
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        return .authorized
    }
}

extension DeepLinkSentinel {
    static let preview: DeepLinkSentinel = {
        let s = DeepLinkSentinel(
            authUI: PreviewDeepLinkAuthUI(),
            authStore: MemoryDeepLinkAuthStore(),
            managementStore: UserDefaultsDeepLinkManagementStore(namespace: "preview", inMemory: true),
            canManageClients: { true }
        )

        Task {
            do {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: "/System/Applications"), includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]) else {
                    throw Failure("Can't enumerate /System/Applications")
                }

                while let url = enumerator.nextObject() as? URL {
                    guard (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .application) == true else { continue }

                    let auth: DeepLinkClientAuthorization = Int.random(in: 0...1024) % 2 == 0 ? .authorized : .denied

                    guard let client = try? DeepLinkClient(url: url) else { continue }
                    try? await s.authStore.setAuthorization(auth, for: client)
                    let descriptor = DeepLinkClientDescriptor(client: client, authorization: auth)
                    try? await s.managementStore.insert(descriptor)
                }

            } catch {
                print("Error populating preview sentinel: \(error)")
            }
        }

        return s
    }()
}

#Preview("Security Settings") {
    SettingsScreen.preview(.security)
}

#Preview("Security Settings (Command Line On)") {
    SettingsScreen.preview(.security, securitySession: .preview(commandLineAccess: true))
}
#endif
