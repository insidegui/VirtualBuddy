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
            InstallerVirtualMachineView(virtualMachine: virtualMachine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VirtualBuddyMonoProgressView(progress: progress, status: Text(""), style: style)
        }
    }
}

private struct InstallerVirtualMachineView: NSViewRepresentable {
    typealias NSViewType = VZVirtualMachineView

    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        VZVirtualMachineView(frame: .zero)
    }

    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        nsView.virtualMachine = virtualMachine
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .install)
}
#endif
