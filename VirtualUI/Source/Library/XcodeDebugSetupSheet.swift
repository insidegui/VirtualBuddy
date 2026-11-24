import MacDebugHost
import ManagedPreferencesUI
import SwiftUI
import UniformTypeIdentifiers
import VirtualCore

@propertyWrapper
private struct DeveloperFeaturesEnabled: DynamicProperty {
    @ObservedObject private var settings = VBSettingsContainer.current
    @ManagedValue(for: .disableDeveloperFeatures, schema: VirtualBuddyManagedPreferences.schema, default: false)
    private var disabledByPolicy: Bool

    var wrappedValue: Bool { settings.settings.developerFeaturesEnabled && !disabledByPolicy }
}

struct XcodeDebugSetupButton: View {
    let vm: VBVirtualMachine
    let action: () -> Void

    @DeveloperFeaturesEnabled private var developerFeaturesEnabled
    @EnvironmentObject private var library: VMLibraryController

    var body: some View {
        if developerFeaturesEnabled && vm.configuration.systemType == .mac {
            Button("Set Up Xcode Debugging…", action: action)
                .disabled(vm.needsInstall || library.duplicatingMachineIdentifiers.contains(vm.id))
        }
    }
}

struct XcodeDebugSetupSheet: View {
    let vmID: UUID
    let vmName: String

    @DeveloperFeaturesEnabled private var developerFeaturesEnabled
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
        XcodeDebugSetupForm(vmName: vmName, projectURL: project?.url, projectError: project?.error,
                            isLoading: project?.isLoading == true, choices: project?.choices.map(\.option) ?? [],
                            selectedID: project.map { Bindable($0).selectedID } ?? .constant(nil),
                            commandsEnabled: commandsEnabled, needsXcodeRelaunch: needsXcodeRelaunch,
                            createdScheme: createdScheme, errorMessage: errorMessage,
                            chooseProject: { choosingProject = true }, enableCommands: enableCommands,
                            createScheme: createScheme)
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
        .onChange(of: developerFeaturesEnabled, initial: true) {
            if !developerFeaturesEnabled { dismiss() }
        }
    }

    private func enableCommands() {
        do {
            try VBSettings.current.requireDeveloperFeatures()
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
            try VBSettings.current.requireDeveloperFeatures()
            createdScheme = try choice.scheme.install(destination: vmID, named: vmName, configuration: VirtualBuddyDebugging.host,
                                                      bindings: VirtualBuddyDebugging.bindings)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct XcodeDebugSetupForm: View {
    let vmName: String
    var projectURL: URL?
    var projectError: String?
    var isLoading = false
    var choices: [SchemePicker.Option] = []
    @Binding var selectedID: UUID?
    var commandsEnabled = false
    var needsXcodeRelaunch = false
    var createdScheme: URL?
    var errorMessage: String?
    let chooseProject: () -> Void
    let enableCommands: () -> Void
    let createScheme: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var selectedChoice: SchemePicker.Option? { choices.first { $0.id == selectedID } }

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
                SetupStep(title: "Project or workspace", complete: projectURL != nil) {
                    if let projectURL {
                        Text(verbatim: projectURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(projectURL.path)
                    }
                } control: {
                    if createdScheme == nil {
                        Button {
                            chooseProject()
                        } label: {
                            Text(projectURL == nil ? "Choose…" : "Change…", bundle: #bundle)
                        }
                    }
                }

                Divider()

                SetupStep(title: "App scheme", complete: selectedChoice != nil) {
                    if let error = projectError {
                        Text(verbatim: error).foregroundStyle(.red)
                    } else if projectURL == nil {
                        Text("Choose a project to see its app schemes.", bundle: #bundle)
                    }
                } control: {
                    if isLoading {
                        ProgressView().controlSize(.small).accessibilityLabel(Text("Finding app schemes", bundle: #bundle))
                    } else if choices.count > 1, createdScheme == nil {
                        SchemePicker(choices: choices, selection: $selectedID)
                    } else if let choice = selectedChoice {
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
                            .disabled(selectedChoice == nil || !commandsEnabled)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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
    struct Option: Identifiable {
        let id: UUID
        let label: String
    }

    let choices: [Option]
    @Binding var selection: UUID?

    var body: some View {
        Picker(selection: $selection) {
            Text("Choose a scheme…", bundle: #bundle).tag(nil as UUID?)
            ForEach(choices) { choice in
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
        var option: SchemePicker.Option { .init(id: id, label: label) }
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

#if DEBUG
private enum SetupPreview {
    static let project = URL(filePath: "/Projects/FieldNotes.xcodeproj")
    static let schemes = ["FieldNotes", "FieldNotes Beta"].map { SchemePicker.Option(id: UUID(), label: $0) }
}

#Preview("Choose a Project") {
    XcodeDebugSetupForm(vmName: "Test Mac", selectedID: .constant(nil),
                        chooseProject: {}, enableCommands: {}, createScheme: {})
}

#Preview("Choose an App Scheme") {
    @Previewable @State var selection: UUID?
    XcodeDebugSetupForm(vmName: "Test Mac", projectURL: SetupPreview.project, choices: SetupPreview.schemes,
                        selectedID: $selection, commandsEnabled: true,
                        chooseProject: {}, enableCommands: {}, createScheme: {})
}

#Preview("Scheme Created") {
    XcodeDebugSetupForm(vmName: "Test Mac", projectURL: SetupPreview.project, choices: SetupPreview.schemes,
                        selectedID: .constant(SetupPreview.schemes[0].id), commandsEnabled: true,
                        needsXcodeRelaunch: true, createdScheme: URL(filePath: "/Schemes/FieldNotes — Test Mac.xcscheme"),
                        chooseProject: {}, enableCommands: {}, createScheme: {})
}

#Preview("Setup Steps") {
    VStack(spacing: 14) {
        SetupStep(title: "Project or workspace", complete: true) {
            Text(verbatim: SetupPreview.project.lastPathComponent)
        } control: { EmptyView() }
        SetupStep(title: "Custom LLDB Commands", complete: false) {
            EmptyView()
        } control: { Button("Enable") {} }
    }
    .padding()
    .frame(width: 480)
}

#Preview("App Scheme Picker") {
    @Previewable @State var selection: UUID?
    SchemePicker(choices: SetupPreview.schemes, selection: $selection)
        .padding()
}
#endif
