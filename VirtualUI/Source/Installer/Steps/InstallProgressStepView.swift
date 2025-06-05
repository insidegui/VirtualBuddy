//
//  InstallProgressStepView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct InstallProgressStepView: View {
    @EnvironmentObject var viewModel: VMInstallationViewModel

    @State private var consoleExpanded = false

    var body: some View {
        VStack {
            loadingView
                .textSelection(.enabled)

            InstallationConsole(isExpanded: $consoleExpanded)
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

struct InstallProgressStepView_Previews: PreviewProvider {
    static var previews: some View {
        InstallProgressStepView()
    }
}
