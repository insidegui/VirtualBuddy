import SwiftUI
import UniformTypeIdentifiers
import VirtualCore

struct XcodeDebugSetupSheet: View {
    let vmID: UUID
    let vmName: String

    @Environment(\.dismiss) private var dismiss

    @State private var choosingProject = false
    @State private var project: SetupProject?
    @State private var commandsEnabled = false
    @State private var needsXcodeRelaunch = false
    @State private var createdScheme: URL?
    @State private var errorMessage: String?

    private static let documentTypes = ["xcodeproj", "xcworkspace"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .package)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set Up Xcode Debugging", bundle: #bundle)
                    .font(.title2.bold())
                Text("To debug on **\(vmName)**, log in to the VM with VirtualBuddyGuest running and Xcode or Apple’s Command Line Tools installed.", bundle: #bundle)
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            VStack(alignment: .leading, spacing: 14) {
                SetupStep(title: "Project or workspace", complete: project != nil) {
                    if let project {
                        Text(verbatim: project.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(project.url.path)
                    }
                } control: {
                    if createdScheme == nil {
                        Button {
                            choosingProject = true
                        } label: {
                            Text(project == nil ? "Choose…" : "Change…", bundle: #bundle)
                        }
                    }
                }

                Divider()

                SetupStep(title: "App scheme", complete: project?.selectedChoice != nil) {
                    if let error = project?.error {
                        Text(verbatim: error).foregroundStyle(.red)
                    } else if project == nil {
                        Text("Choose a project to see its app schemes.", bundle: #bundle)
                    }
                } control: {
                    if let project, project.isLoading {
                        ProgressView().controlSize(.small).accessibilityLabel(Text("Finding app schemes", bundle: #bundle))
                    } else if let project, project.choices.count > 1, createdScheme == nil {
                        SchemePicker(project: project)
                    } else if let choice = project?.selectedChoice {
                        Text(verbatim: choice.label).lineLimit(1).truncationMode(.middle)
                    }
                }

                Divider()

                SetupStep(title: "Custom LLDB Commands", complete: commandsEnabled) {
                    if needsXcodeRelaunch {
                        Text("Quit and reopen Xcode before running the scheme.", bundle: #bundle)
                    } else if !commandsEnabled {
                        Text("Enable this experimental Xcode setting to connect its debugger to the VM. You’ll need to relaunch Xcode.", bundle: #bundle)
                    }
                } control: {
                    if !commandsEnabled {
                        Button { enableCommands() } label: { Text("Enable", bundle: #bundle) }
                    }
                }

                Divider()

                SetupStep(title: "VM run scheme", complete: createdScheme != nil) {
                    if let createdScheme {
                        let name = createdScheme.deletingPathExtension().lastPathComponent
                        Text("In Xcode, select **\(name)** and **My Mac**, then press **⌘R**. The first run caches symbols for this version of macOS.", bundle: #bundle)
                            .textSelection(.enabled)
                    } else {
                        Text("The scheme will be saved in your Xcode user data.", bundle: #bundle)
                    }
                } control: { EmptyView() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Label { Text(verbatim: errorMessage) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    if createdScheme != nil {
                        Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                            .keyboardShortcut(.cancelAction)
                        Button { createScheme() } label: { Text("Create Scheme", bundle: #bundle) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(project?.selectedChoice == nil || !commandsEnabled)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingProject, allowedContentTypes: Self.documentTypes) { result in
            do {
                project = SetupProject(url: try result.get())
                errorMessage = nil
            } catch let error as CocoaError where error.code == .userCancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .task(id: project?.id) { await project?.loadChoices() }
        .onAppear { commandsEnabled = CustomLLDBCommands.isEnabled }
        .onChange(of: project?.selectedID) { errorMessage = nil }
    }

    private func enableCommands() {
        do {
            if !CustomLLDBCommands.isEnabled {
                try CustomLLDBCommands.enable()
                needsXcodeRelaunch = true
            }
            commandsEnabled = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createScheme() {
        guard let choice = project?.selectedChoice else { return }
        commandsEnabled = CustomLLDBCommands.isEnabled
        guard commandsEnabled else { return }
        do {
            createdScheme = try choice.scheme.install(vm: vmID, named: vmName, app: Bundle.main.bundleURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetupStep<Detail: View, Control: View>: View {
    let title: LocalizedStringKey
    let complete: Bool
    @ViewBuilder let detail: Detail
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(complete ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title, bundle: #bundle)
                    .font(.headline)
                    .accessibilityValue(Text(complete ? "Complete" : "Incomplete", bundle: #bundle))
                detail.foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            control
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SchemePicker: View {
    @Bindable var project: SetupProject

    var body: some View {
        Picker(selection: $project.selectedID) {
            Text("Choose a scheme…", bundle: #bundle).tag(nil as UUID?)
            ForEach(project.choices) { choice in
                Text(verbatim: choice.label).tag(Optional(choice.id))
            }
        } label: { Text("App scheme", bundle: #bundle) }
        .labelsHidden()
        .frame(maxWidth: 250, alignment: .trailing)
    }
}

@MainActor @Observable
private final class SetupProject: Identifiable {
    let id = UUID()
    let url: URL
    private let securityScoped: Bool
    private(set) var choices: [Choice] = []
    private(set) var isLoading = true
    private(set) var error: String?
    var selectedID: UUID?

    var selectedChoice: Choice? { choices.first { $0.id == selectedID } }

    init(url: URL) {
        self.url = url
        securityScoped = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if securityScoped { url.stopAccessingSecurityScopedResource() }
    }

    func loadChoices() async {
        guard isLoading else { return }
        do {
            let found = try await Choice.discover(in: url)
            try Task.checkCancellation()
            guard !found.isEmpty else { throw Failure("This project or workspace has no runnable macOS app schemes or app targets.") }
            choices = found
            selectedID = found.count == 1 ? found[0].id : nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    struct Choice: Identifiable {
        let id = UUID()
        let label: String
        let scheme: DebugScheme

        @concurrent static func discover(in url: URL) async throws -> sending [Self] {
            let schemes = try DebugScheme.choices(in: url)
            let groups = Dictionary(grouping: schemes, by: \.name)
            return schemes.map { scheme in
                let label = groups[scheme.name]?.count == 1 ? scheme.name : "\(scheme.name) (\(scheme.projectName))"
                return Self(label: label, scheme: scheme)
            }
        }
    }
}

private enum CustomLLDBCommands {
    static let key = "IDEDebuggerFeatureSetting" as CFString
    static let domain = "com.apple.dt.Xcode" as CFString
    static let mask = 12
    static var flags: Int { (CFPreferencesCopyAppValue(key, domain) as? NSNumber)?.intValue ?? 0 }
    static var isEnabled: Bool { flags & mask == mask }

    static func enable() throws {
        CFPreferencesSetAppValue(key, NSNumber(value: flags | mask), domain)
        guard CFPreferencesAppSynchronize(domain), isEnabled else { throw Failure("Could not enable Custom LLDB Commands in Xcode.") }
    }
}
