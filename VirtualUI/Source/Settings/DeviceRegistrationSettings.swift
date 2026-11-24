import AppStoreConnectDevices
import SwiftUI
import UniformTypeIdentifiers
import VirtualCore

struct DeviceRegistrationSettings: View {
    private let keys = XcodeProvisioningController.shared.keys
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
            SettingsCaption("An optional App Store Connect team key lets VirtualBuddy register a VM with your signing team. The private key is stored in this Mac’s Keychain.")
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .task { await reload() }
        .sheet(isPresented: $editing, onDismiss: { Task { await reload() } }) { RegistrationKeyEditor(keys: keys) }
        .confirmationDialog("Remove this team’s API key from this Mac?", isPresented: Binding(
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
    let keys: DeviceRegistrationKeys
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

    init(keys: DeviceRegistrationKeys, signingTeam: String? = nil) {
        self.keys = keys
        self.signingTeam = signingTeam
        _team = State(initialValue: signingTeam ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App Store Connect Team Key").font(.headline)
            Text("Choose an App Store Connect team key with permission to register devices for the signing team shown in Xcode.")
            Link("Manage Team Keys in App Store Connect", destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!)
            Form {
                if let signingTeam {
                    LabeledContent("Signing team ID", value: signingTeam)
                } else {
                    TextField("Signing team ID", text: $team)
                }
                TextField("Issuer ID", text: $issuer)
                TextField("Key ID", text: $keyID)
                LabeledContent("Private key") {
                    Button(file?.lastPathComponent ?? "Choose .p8 File…") { choosing = true }
                }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Key") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(team.isEmpty || keyID.isEmpty || issuerID == nil || file == nil)
            }
        }
        .disabled(saving)
        .padding(20)
        .frame(width: 440)
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
