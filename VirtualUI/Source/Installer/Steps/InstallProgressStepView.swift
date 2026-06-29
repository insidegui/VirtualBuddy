//
//  InstallProgressStepView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore
import Virtualization

struct InstallProgressStepView: View {
    @EnvironmentObject var viewModel: VMInstallationViewModel

    private var progress: Double? {
        switch viewModel.state {
        case .loading(let progress, _): progress ?? 0
        case .idle: 0
        case .error: nil
        }
    }

    private var status: Text? {
        switch viewModel.state {
            case .loading(_, let info): info.flatMap { Text($0) }
            case .error(let message): Text(message)
            case .idle: Text("Installing")
        }
    }

    private var style: VirtualBuddyMonoStyle {
        switch viewModel.state {
        case .idle, .loading: .default
        case .error: .failure
        }
    }

    var body: some View {
        if let status {
            VirtualBuddyMonoProgressView(progress: progress, status: status, style: style)
                .textSelection(.enabled)
        } else if let virtualMachine = viewModel.virtualMachine {
            SwiftUIVMView(controllerState: .constant(.running(virtualMachine)), captureSystemKeys: false, isDFUModeVM: false, automaticallyReconfiguresDisplay: .constant(false))
                .virtualMachineInteractionDisabled()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VirtualBuddyMonoProgressView(progress: progress, status: Text(""), style: style)
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .install)
}
#endif
