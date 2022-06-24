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
            collectionView(with: vms)
        case .loading:
            ProgressView()
        case .failed(let error):
            Text(error.errorDescription!)
        }
    }

    @ViewBuilder
    private func collectionView(with vms: [VBVirtualMachine]) -> some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(vms) { vm in
                    Button {
                        launch(vm)
                    } label: {
                        Text(vm.name)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(VirtualMachineButtonStyle(vm: vm))
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
        openWindow {
            VirtualMachineSessionView(controller: VMController(with: vm))
                .environmentObject(library)
        }
    }

    private func launchInstallWizard() {
        openWindow {
            VMInstallationWizard()
                .environmentObject(library)
        }
    }
    
}

struct VirtualMachineButtonStyle: ButtonStyle {

    let vm: VBVirtualMachine

    func makeBody(configuration: Configuration) -> some View {
        LibraryItemView(
            vm: vm,
            isPressed: configuration.isPressed,
            label: { configuration.label }
        )
    }

}

struct LibraryItemView<Label>: View where Label: View {

    var vm: VBVirtualMachine
    var isPressed = false
    var label: () -> Label

    var body: some View {
        VStack(spacing: 12) {
            thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 4)

            label()
        }
        .padding([.leading, .trailing, .top], 8)
        .padding(.bottom, 12)
        .background(Material.thin, in: backgroundShape)
        .clipShape(backgroundShape)
        .background {
            if let image = vm.generateThumbnail() {
                Image(nsImage: image)
                    .resizable()
                    .blur(radius: 22)
                    .opacity(isPressed ? 0.1 : 0.4)
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 12)
        .shadow(color: Color.black.opacity(0.56), radius: 1)
        .scaleEffect(isPressed ? 0.96 : 1)
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = vm.generateThumbnail() {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                .clipped()
                .aspectRatio(16/9, contentMode: .fit)
        } else {
            ZStack {
                Image(systemName: "photo.fill")
                    .font(.title)
                    .opacity(0.6)

                Rectangle()
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: 140)
        }
    }

}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
    }
}
