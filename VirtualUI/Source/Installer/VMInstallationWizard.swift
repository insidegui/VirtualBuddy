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

    @Environment(\.dismiss) var closeWindow

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

    private var hideBottomBar: Bool {
        switch viewModel.step {
        case .systemType, .restoreImageInput, .restoreImageSelection, .name:
            false
        case .configuration, .download, .install, .done:
            true
        }
    }

    @State private var showingConsole = false

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
                    case .download, .install, .done:
                        InstallProgressDisplayView().environmentObject(viewModel)
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
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    if viewModel.step == .done {
                        closeWindow()
                    } else {
                        viewModel.back()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canGoBack)
            }

            ToolbarItemGroup(placement: .confirmationAction) {
                if viewModel.step == .done {
                    Button("Done") {
                        closeWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.step == .install {
                    Toggle(isOn: $showingConsole) {
                        Image(systemName: "terminal")
                    }
                    .help("Logs")
                }
            }
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showingConsole {
                InstallationConsole()
                    .padding(.horizontal, Self.padding * 2)
                    .padding(.bottom, Self.padding)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: showingConsole)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hideBottomBar {
                bottomBar
            }
        }
        .background {
            BlurHashFullBleedBackground(blurHash: viewModel.data.backgroundHash)
                .fullBleedBackgroundDimmed(dimBackground)
        }
        .environment(\.containerPadding, Self.padding)
        .environment(\.maxContentWidth, effectiveMaxContentWidth)
        .confirmBeforeClosingWindow { [weak viewModel] in
            await viewModel?.confirmBeforeClosing() ?? true
        }
    }

    private var dimBackground: Bool {
        switch viewModel.step {
        case .systemType: false
        case .restoreImageInput: false
        case .restoreImageSelection: false
        case .name: false
        case .configuration: false
        case .download: true
        case .install: true
        case .done: false
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Group {
                switch viewModel.step {
                case .restoreImageSelection:
                    HStack(spacing: 12) {
                        Button("Local File") {
                            viewModel.selectInstallMethod(.localFile)
                        }

                        Divider()
                            .frame(height: 22)

                        Button("Custom Link") {
                            viewModel.selectInstallMethod(.remoteManual)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .buttonStyle(.link)

            if case .error(let message) = viewModel.state {
                Spacer()

                errorView(message: message, multiline: false)
            }

            Spacer()

            if viewModel.showNextButton {
                nextButton
            }
        }
        .virtualBuddyBottomBarStyle()
    }

    @ViewBuilder
    private func errorView(message: String, multiline: Bool) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
            .lineLimit(multiline ? nil : 1)
            .minimumScaleFactor(0.8)
            .help(message)
    }

    @ViewBuilder
    private var nextButton: some View {
        Button(viewModel.buttonTitle, action: {
            if viewModel.step == .done {
                library.loadMachines()
                closeWindow()
            } else {
                viewModel.next()
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
        RestoreImageURLInputView().environmentObject(viewModel)
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

                viewModel.next()
            }
        } else {
            preparingStatus
        }
    }

    @ViewBuilder
    private var preparingStatus: some View {
        Text("Preparing…")
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var renameVM: some View {
        VirtualMachineNameInputView(name: $viewModel.data.name)
    }

}

extension VMInstallationStep {
    var subtitle: String {
        switch self {
        case .systemType: "Choose Operating System"
        case .restoreImageInput: "Select Custom Restore Image"
        case .restoreImageSelection: "Choose Version"
        case .name: "Name Your Virtual Machine"
        case .configuration: "Configure Your Virtual Machine"
        case .download: "Downloading"
        case .install: "Installing"
        case .done: "Finished"
        }
    }
}

extension View {
    @ViewBuilder
    func virtualBuddyBottomBarStyle() -> some View {
        frame(maxWidth: .infinity)
            .controlSize(.large)
            .padding()
            .background(Material.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

#if DEBUG
extension VMInstallationWizard {
    @ViewBuilder
    static func preview(step: VMInstallationStep) -> some View {
        VMInstallationWizard(library: .preview, initialStep: step)
            .frame(width: 900)
    }

    @ViewBuilder
    static var preview: some View {
        preview(step: .restoreImageSelection)
    }
}

#Preview {
    VMInstallationWizard.preview(step: .install)
}
#endif // DEBUG
