//
//  InstallProgressDoneView.swift
//  VirtualBuddy
//
//  Created by Michael Fey on 3/10/26.
//


import SwiftUI
import VirtualCore
import BuddyKit

struct InstallProgressDoneView: View {
    @EnvironmentObject private var viewModel: VMInstallationViewModel
    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                VirtualBuddyMonoIcon(style: .success)

                Text(viewModel.data.systemType.installFinishedMessage)
                    .font(.subheadline)

                if let machine = viewModel.machine {
                    launchButton(for: machine)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(.green)
            .tint(.green)

            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func launchButton(for machine: VBVirtualMachine) -> some View {
        ZStack {
            Button("Let\u{2019}s Go!") {
                launch(machine)
            }
            .foregroundStyle(Color(white: 0.03))
            .controlSize(.large)
            .accessibilityHint("Launches the new virtual machine")

            // This is a hidden button that exists purely to accept the keyboardShortcut(.defaultAction) for this window. Setting a default action for a button overrides the foreground styling on the button leaving white text on a lighter green background, which is difficult to read.
            Button("") {
                launch(machine)
            }
            .keyboardShortcut(.defaultAction)
            .labelsHidden()
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func launch(_ machine: VBVirtualMachine) {
        sessionManager.launch(machine, library: library, options: nil)
        dismiss()
    }
}
