//
//  VMInstallationWizard.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore
import Combine

extension EnvironmentValues {
    /// Defines the padding for a container where the children must adopt the padding in their implementations.
    /// Currently used for the `VMInstallationWizard` to allow children to apply padding in a custom way,
    /// retaining the standard padding between all steps.
    @Entry var containerPadding: CGFloat = 16

    /// The maximum width for the content area in the current context.
    @Entry var maxContentWidth: CGFloat? = nil
}

public struct VMInstallationWizard: View {
    static var padding: CGFloat { 22 }
    static var maxContentWidth: CGFloat { 720 }

    @ObservedObject var library: VMLibraryController
    @StateObject var viewModel: VMInstallationViewModel

    @Environment(\.closeWindow) var closeWindow

    public init(library: VMLibraryController, restoringAt restoreURL: URL? = nil, initialStep: VMInstallationStep? = nil) {
        self._library = .init(initialValue: library)
        self._viewModel = .init(wrappedValue: VMInstallationViewModel(library: library, restoringAt: restoreURL, initialStep: initialStep))
    }

    private let stepValidationStateChanged = PassthroughSubject<Bool, Never>()

    /// Some step views can't have the default padding applied because they need
    /// to handle padding in a specific way. Those may read `containerPadding` from the environment.
    private var effectivePadding: CGFloat {
        switch viewModel.step {
        case .restoreImageSelection, .configuration: 0
        default: Self.padding
        }
    }

    private var effectiveMaxContentWidth: CGFloat {
        switch viewModel.step {
        case .configuration: VMConfigurationSheet.minWidth
        default: Self.maxContentWidth
        }
    }

    public var body: some View {
        NavigationStack {
            VStack {
                switch viewModel.step {
                    case .systemType:
                        guestSystemTypeSelection
                    case .restoreImageInput:
                        restoreImageURLInput
                    case .restoreImageSelection:
                        restoreImageSelection
                    case .configuration:
                        configureVM
                    case .name:
                        renameVM
                    case .download:
                        downloadView
                    case .install:
                        installProgress
                    case .done:
                        finishingLine
                }
            }
            .onReceive(stepValidationStateChanged) { isValid in
                viewModel.disableNextButton = !isValid
            }
            .navigationTitle(Text("Virtual Machine Setup"))
            .navigationSubtitle(Text(viewModel.step.subtitle))
            .padding(effectivePadding)
        }
        .toolbar {
            Text("").hidden()
        }
        .background {
            BlurHashFullBleedBackground(viewModel.data.backgroundHash)
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .environment(\.containerPadding, Self.padding)
        .environment(\.maxContentWidth, effectiveMaxContentWidth)
    }
    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Group {
                switch viewModel.step {
                case .restoreImageSelection:
                    HStack(spacing: 12) {
                        Button("Local File") {
                            viewModel.setInstallMethod(.localFile)
                        }

                        Divider()
                            .frame(height: 22)

                        Button("Custom Link") {
                            viewModel.setInstallMethod(.remoteManual)
                        }
                    }
                case .restoreImageInput:
                    /// Allow going back to remote options selection after going to custom file/url.
                    Button("Back") {
                        viewModel.back()
                    }
                default:
                    EmptyView()
                }
            }
            .buttonStyle(.link)

            Spacer()

            nextButton
        }
        .controlSize(.large)
        .padding()
        .background(Material.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var nextButton: some View {
        Button(viewModel.buttonTitle, action: {
            if viewModel.step == .done {
                library.loadMachines()
                closeWindow()
            } else {
                viewModel.goNext()
            }
        })
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.disableNextButton)
    }

    @ViewBuilder
    private var guestSystemTypeSelection: some View {
        GuestTypePicker(selection: $viewModel.data.systemType)
    }

    @ViewBuilder
    private var restoreImageURLInput: some View {
        TextField("URL", text: $viewModel.provisionalRestoreImageURL, onCommit: viewModel.goNext)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
    }

    @ViewBuilder
    private var restoreImageSelection: some View {
        RestoreImageSelectionStep()
            .environmentObject(viewModel)
    }
    
    @ViewBuilder
    private var configureVM: some View {
        if let machine = viewModel.machine {
            InstallConfigurationStepView(vm: machine) { configuredModel in
                viewModel.machine = configuredModel
                try? viewModel.machine?.saveMetadata()

                viewModel.goNext()
            }
        } else {
            preparingStatus
        }
    }

    @ViewBuilder
    private var preparingStatus: some View {
        Text("Preparing…")
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var renameVM: some View {
        VirtualMachineNameField(name: $viewModel.data.name)
    }

    private var vmDisplayName: String {
        viewModel.data.name.isEmpty ? viewModel.data.systemType.name : viewModel.data.name
    }

    @ViewBuilder
    private var downloadView: some View {
        if let downloader = viewModel.downloader {
            RestoreImageDownloadView(downloader: downloader)
        } else {
            preparingStatus
        }
    }

    @ViewBuilder
    private var installProgress: some View {
        InstallProgressStepView()
            .environmentObject(viewModel)
    }

    @ViewBuilder
    private var finishingLine: some View {
        VStack {
            InstallationWizardTitle(vmDisplayName)

            Text(viewModel.data.systemType.installFinishedMessage)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        switch viewModel.state {
            case .loading(let progress, let info):
                VStack {
                    ProgressView(value: progress) { }
                        .progressViewStyle(.linear)
                        .labelsHidden()

                    if let info = info {
                        Text(info)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            case .error(let message):
                Text(message)
            case .idle:
                Text("Starting…")
                    .foregroundColor(.secondary)
        }
    }

}

#if DEBUG
extension VMInstallationWizard {
    @ViewBuilder
    static var preview: some View {
        VMInstallationWizard(library: .preview, initialStep: .restoreImageSelection)
            .frame(width: 900)
    }
}

#Preview {
    VMInstallationWizard.preview
}
#endif
