import SwiftUI
import VirtualUI
import VirtualWormhole

/// The contents of the panel shown from the VirtualBuddyGuest menu bar item.
struct GuestDashboard: View {
    @Environment(GuestLaunchAtLoginManager.self) private var launchAtLoginManager
    @Environment(GuestHostSession.self) private var hostSession
    @Environment(GuestSharedFoldersManager.self) private var sharedFolders
    @Environment(\.guestDashboardActions) private var actions

    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            separator

            VStack(spacing: 0) {
                sharedFoldersRow

                serviceTunnelsRow

                #if ENABLE_USERDEFAULTS_SYNC
                defaultsImportRow
                #endif
            }
            .padding(GuestDashboardMetrics.rowInset)

            separator

            launchAtLoginToggle

            separator

            quitRow
        }
        .buttonStyle(.guestDashboardRow)
        .frame(width: GuestDashboardMetrics.width)
    }

    private var separator: some View {
        Divider()
            .padding(.horizontal, GuestDashboardMetrics.contentInset)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("VirtualBuddy Guest")
                    .font(.headline)

                HStack(spacing: 5) {
                    Circle()
                        .fill(hostSession.isConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)

                    Text(hostSession.isConnected ? "Connected to VirtualBuddy" : "Not Connected")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GuestDashboardMetrics.contentInset)
        .padding(.vertical, 14)
    }

    // MARK: - Features

    @ViewBuilder
    private var sharedFoldersRow: some View {
        Button {
            sharedFolders.revealInFinder()
            actions.dismiss()
        } label: {
            GuestDashboardRowLabel("Shared Folders", subtitle: sharedFoldersSubtitle, systemImage: "folder")
        }
    }

    private var sharedFoldersSubtitle: Text {
        if let error = sharedFolders.error {
            Text("Failed to mount: \(error.localizedDescription)")
                .foregroundStyle(.red)
        } else {
            Text("Show in Finder")
        }
    }

    @ViewBuilder
    private var serviceTunnelsRow: some View {
        Button {
            actions.showWindow(.serviceTunnels)
        } label: {
            GuestDashboardRowLabel(title: "Service Tunnels", subtitle: Text(serviceTunnelsSubtitle), systemImage: "arrow.left.arrow.right") {
                Image(systemName: "chevron.forward")
            }
        }
    }

    private var serviceTunnelsSubtitle: String {
        let tunnels = hostSession.tunnels

        guard tunnels.available else { return "Not available" }

        let activeCount = tunnels.rules.count
        let requestCount = tunnels.requests.count

        guard activeCount > 0 || requestCount > 0 else { return "None configured" }

        var components = [String]()

        if activeCount > 0 {
            components.append(activeCount == 1 ? "1 tunnel" : "\(activeCount) tunnels")
        }

        if requestCount > 0 {
            components.append("\(requestCount) awaiting approval")
        }

        return components.joined(separator: " · ")
    }

    #if ENABLE_USERDEFAULTS_SYNC
    @ViewBuilder
    private var defaultsImportRow: some View {
        Button {
            actions.showWindow(.defaultsImport)
        } label: {
            GuestDashboardRowLabel(title: "Defaults Import", subtitle: Text("Import app preferences from the host"), systemImage: "square.and.arrow.down") {
                Image(systemName: "chevron.forward")
            }
        }
    }
    #endif

    // MARK: - Settings

    @ViewBuilder
    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at Login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, GuestDashboardMetrics.contentInset)
        .padding(.vertical, 10)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginManager.isLaunchAtLoginEnabled
        } set: { isEnabled in
            Task {
                do {
                    try await launchAtLoginManager.setLaunchAtLoginEnabled(isEnabled)

                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Quit

    @ViewBuilder
    private var quitRow: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack {
                Text("Quit VirtualBuddy Guest")

                Spacer()

                Text("⌘Q")
                    .foregroundStyle(.tertiary)
            }
        }
        .keyboardShortcut("q")
        .padding(GuestDashboardMetrics.rowInset)
    }
}

#if DEBUG
#Preview {
    GuestDashboard()
        .environment(GuestLaunchAtLoginManager())
        .environment(GuestHostSession())
        .environment(GuestSharedFoldersManager())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StatusBarMenuChromeMetrics.cornerRadius, style: .continuous))
        .padding(32)
}
#endif
