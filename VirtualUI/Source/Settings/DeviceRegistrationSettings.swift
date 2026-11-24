import AppStoreConnectDevices
import SwiftUI
import UniformTypeIdentifiers
import VirtualCore

protocol RegistrationKeyStore: Sendable {
    func teams() async throws -> [String]
    func remove(teamID: String) async throws
    func save(teamID: String, issuerID: UUID, keyID: String, privateKeyFile: URL) async throws
}

extension DeviceRegistrationKeys: RegistrationKeyStore {}

struct DeviceRegistrationSettings: View {
    let keys: any RegistrationKeyStore
    @State private var teams: [String] = []
    @State private var editing = false
    @State private var removing: String?
    @State private var error: String?

    var body: some View {
        SettingsRow("Device registration:") {
            ForEach(teams, id: \.self) { team in
                HStack {
                    Text("Team \(team)").font(.body.monospacedDigit())
                    Spacer()
                    Button("Remove…") { removing = team }
                }
            }
            Button("Add Team API Key…") { editing = true }
            SettingsCaption("An optional App Store Connect team key lets VirtualBuddy register a virtual machine with your signing team. The private key is stored in the host Mac’s Keychain, and VirtualBuddy asks for Touch ID or your password before using it.")
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .task { await reload() }
        .sheet(isPresented: $editing, onDismiss: { Task { await reload() } }) { RegistrationKeyEditor(keys: keys) }
        .confirmationDialog("Remove this team’s API key from the host Mac’s Keychain?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), presenting: removing) { team in
            Button("Remove Key", role: .destructive) {
                Task {
                    do { try await keys.remove(teamID: team); await reload() }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { _ in Text("Your registered devices and the key in App Store Connect are unaffected.") }
    }

    private func reload() async {
        do { teams = try await keys.teams(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct RegistrationKeyEditor: View {
    let keys: any RegistrationKeyStore
    let signingTeam: String?
    @Environment(\.dismiss) private var dismiss
    @State private var team: String
    @State private var issuer = ""
    @State private var keyID = ""
    @State private var file: URL?
    @State private var choosing = false
    @State private var saving = false
    @State private var error: String?

    private var issuerID: UUID? { UUID(uuidString: issuer.trimmingCharacters(in: .whitespacesAndNewlines)) }

    init(keys: any RegistrationKeyStore, signingTeam: String? = nil) {
        self.keys = keys
        self.signingTeam = signingTeam
        _team = State(initialValue: signingTeam ?? "")
    }

    var body: some View {
        XcodeRunSheet(title: "Add Team API Key",
                      subtitle: "Choose an App Store Connect team key with permission to register devices. The private key is stored in the host Mac’s Keychain, and VirtualBuddy asks for Touch ID or your password before using it.") {
            XcodeRunRow(symbol: "key", title: "App Store Connect Credentials") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Signing team")
                        if let signingTeam {
                            Text(signingTeam).textSelection(.enabled)
                        } else {
                            TextField("Signing team ID", text: $team)
                        }
                    }
                    GridRow {
                        Text("Issuer ID")
                        TextField("Issuer ID", text: $issuer)
                    }
                    GridRow {
                        Text("Key ID")
                        TextField("Key ID", text: $keyID)
                    }
                    GridRow {
                        Text("Private key")
                        Button(file?.lastPathComponent ?? "Choose .p8 File…") { choosing = true }
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                Link("Manage Team Keys in App Store Connect", destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!)
                    .foregroundStyle(.tint)
            }
            if let error {
                XcodeRunRow(symbol: "exclamationmark.triangle", title: "Couldn’t Save Key") {
                    Text(error).textSelection(.enabled)
                }
            }
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .airGlassButtonStyle()
            Button("Save Key") { save() }
                .keyboardShortcut(.defaultAction)
                .airGlassButtonStyle(prominent: true)
                .disabled(team.isEmpty || keyID.isEmpty || issuerID == nil || file == nil)
        }
        .disabled(saving)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data]) { result in
            do {
                let url = try result.get()
                file = url
                let name = url.deletingPathExtension().lastPathComponent
                if name.hasPrefix("AuthKey_") { keyID = String(name.dropFirst("AuthKey_".count)) }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        guard let file, let issuerID else { return }
        saving = true
        Task {
            defer { saving = false }
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            do {
                try VBSettings.current.requireDeveloperFeatures()
                try await keys.save(teamID: team.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                    issuerID: issuerID, keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                    privateKeyFile: file)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

#if DEBUG
actor PreviewRegistrationKeys: RegistrationKeyStore {
    private var teamIDs: Set<String>

    init(teams: Set<String> = []) {
        teamIDs = teams
    }

    func teams() -> [String] { teamIDs.sorted() }
    func remove(teamID: String) { teamIDs.remove(teamID) }
    func save(teamID: String, issuerID: UUID, keyID: String, privateKeyFile: URL) { teamIDs.insert(teamID) }
}

private extension DeviceRegistrationSettings {
    init(previewTeams: [String]) {
        self.init(keys: PreviewRegistrationKeys(teams: Set(previewTeams)))
        _teams = State(initialValue: previewTeams)
    }
}

#Preview("Device Registration") {
    SettingsPane {
        DeviceRegistrationSettings(previewTeams: ["EXAMPLE123", "EXAMPLE456"])
    }
}

#Preview("Add Team API Key") {
    RegistrationKeyEditor(keys: PreviewRegistrationKeys())
}

#Preview("Add Key for Signing Team") {
    RegistrationKeyEditor(keys: PreviewRegistrationKeys(), signingTeam: "EXAMPLE123")
}
#endif
