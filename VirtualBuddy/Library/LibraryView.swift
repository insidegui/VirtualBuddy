//
//  LibraryView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import VirtualCore

struct LibraryView: View {
    @StateObject private var library: VMLibraryController
    
    init() {
        self._library = .init(wrappedValue: .shared)
    }
    
    var body: some View {
        libraryContents
            .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .toolbar(content: { toolbarContents })
    }
    
    @State private var selection: VBVirtualMachine?
    
    @ViewBuilder
    private var libraryContents: some View {
        switch library.state {
        case .loaded(let vms):
            collectionView(with: vms)
        case .loading:
            ProgressView()
        case .failed(let error):
            Text(error.errorDescription!)
        }
    }

    @ViewBuilder
    private func collectionView(with vms: [VBVirtualMachine]) -> some View {
        List(selection: $selection) {
            ForEach(vms) { vm in
                Text(vm.name)
                    .tag(vm)
            }
        }
    }
    
    private var toolbarContents: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                guard let selection = selection else {
                    return
                }

                launch(selection)
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(selection == nil)
        }
    }
    
    @Environment(\.openCocoaWindow) private var openWindow
    
    private func launch(_ vm: VBVirtualMachine) {
        openWindow {
            VirtualMachineSessionView(controller: VMController(with: vm))
                .environmentObject(library)
        }
    }
    
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
