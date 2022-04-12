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
        Group {
            if let currentVMController = currentVMController {
                vmContents(with: currentVMController)
                    .toolbar(content: { toolbarContentsVM })
            } else {
                libraryContents
                    .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
                    .toolbar(content: { toolbarContents })
            }
        }
    }
    
    @State private var selection: VBVirtualMachine?
    @State private var currentVMController: VMController?
    
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
    private func vmContents(with controller: VMController) -> some View {
        VirtualMachineSessionView()
            .navigationTitle(controller.virtualMachineModel.name)
            .environmentObject(controller)
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

                currentVMController = VMController(with: selection)
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(selection == nil)
        }
    }
    
    @State private var isShowingGoBackConfirmation = false
    
    private var toolbarContentsVM: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                if isVMRunning {
                    isShowingGoBackConfirmation = true
                } else {
                    goBackToLibrary()
                }
            } label: {
                Image(systemName: "chevron.backward")
            }
            .confirmationDialog("This will stop \(currentVMController!.virtualMachineModel.name). Would you like to continue?", isPresented: $isShowingGoBackConfirmation) {
                Button {
                    goBackToLibrary()
                } label: {
                    Text("Stop")
                }
            }
        }
    }
    
    private func goBackToLibrary() {
        guard let controller = currentVMController else {
            return
        }
        guard isVMRunning else {
            self.currentVMController = nil
            return
        }
        
        Task {
            try await controller.stop()
            
            self.currentVMController = nil
        }
    }
    
    private var isVMRunning: Bool {
        guard let controller = currentVMController else {
            return false
        }
        if case .running = controller.state {
            return true
        } else {
            return false
        }
    }
    
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
