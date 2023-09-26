//
//  LibraryView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import VirtualCore

public struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager

    public init() { }

    public var body: some View {
        libraryContents
            .frame(minWidth: 600, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .toolbar(content: { toolbarContents })
            .onOpenURL { url in
                guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]) else { return }
                guard values.contentType == .virtualBuddyVM else { return }

                if let loadedVM = library.virtualMachines.first(where: { $0.bundleURL.path == url.path }) {
                    launch(loadedVM)
                } else {
                    guard let vm = try? VBVirtualMachine(bundleURL: url) else {
                        return
                    }

                    launch(vm)
                }
            }
    }

    private var gridSpacing: CGFloat { 16 }
    private var gridItemMinSize: CGFloat { 240 }
    private var gridColumns: [GridItem] {
        [.init(.adaptive(minimum: gridItemMinSize), spacing: gridSpacing)]
    }
    
    @ViewBuilder
    private var libraryContents: some View {
        switch library.state {
        case .loaded(let vms):
            if vms.isEmpty {
                emptyLibraryView
            } else {
                collectionView(with: vms)
            }
        case .loading:
            ProgressView()
        case .failed(let error):
            Text(error.errorDescription!)
        }
    }

    @ViewBuilder
    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Text("Your Library is Empty")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("VirtualBuddy is looking for virtual machines in **\(library.libraryURL.collapsedHomePath)**. You can change this in the app's settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Create Your First VM") {
                launchInstallWizard()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top)
        }
        .frame(maxWidth: 400)
    }

    @ViewBuilder
    private func collectionView(with vms: [VBVirtualMachine]) -> some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(vms) { vm in
                    Button(vm.name) {
                        launch(vm)
                    }
                    .buttonStyle(VirtualMachineButtonStyle(vm: vm))
                    .environmentObject(library)
                }
            }
            .padding()
            .padding(.top)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContents: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                launchInstallWizard()
            } label: {
                Image(systemName: "plus")
            }
            .help("Install new VM")
        }
    }
    
    @Environment(\.openCocoaWindow) private var openWindow
    
    private func launch(_ vm: VBVirtualMachine) {
        guard !vm.needsInstall else {
            recoverInstallation(for: vm)
            return
        }

        openWindow(id: vm.id) {
            VirtualMachineSessionView(controller: VMController(with: vm), ui: VirtualMachineSessionUI(with: vm))
                .environmentObject(library)
                .environmentObject(sessionManager)
        }
    }

    private func recoverInstallation(for vm: VBVirtualMachine) {
        let alert = NSAlert()
        alert.messageText = "Finish Installation"
        alert.informativeText = "In order to start this virtual machine, its operating system needs to be installed. Would you like to install it now?"
        alert.addButton(withTitle: "Install")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let choice = alert.runModal()

        switch choice {
        case .alertFirstButtonReturn:
            launchInstallWizard(restoring: vm)
        case .alertSecondButtonReturn:
            library.performMoveToTrash(for: vm)
        default:
            break
        }
    }

    private func launchInstallWizard(restoring restoreVM: VBVirtualMachine? = nil) {
        openWindow {
            VMInstallationWizard(restoring: restoreVM)
                .environmentObject(library)
        }
    }
    
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}

fileprivate extension URL {
    var collapsedHomePath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
