//
//  LibraryView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import VirtualCore

public extension String {
    static let vb_libraryWindowID = "library"
}

public struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager

    @Environment(\.openCocoaWindow)
    private var openCocoaWindow

    public init() { }

    public var body: some View {
        libraryContents
            .frame(minWidth: 600, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .toolbar(content: { toolbarContents })
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
                sessionManager.launchInstallWizard(library: library)
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
                    Button {
                        sessionManager.launch(vm, library: library, options: nil)
                    } label: {
                        LibraryItemView(vm: vm, name: vm.name)
                    }
                    .buttonStyle(.vbLibraryItem)
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
                openCocoaWindow {
                    VMInstallationWizard(library: library)
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("New virtual machine")
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
