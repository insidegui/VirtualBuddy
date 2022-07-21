//
//  LibraryItemView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 21/07/22.
//

import SwiftUI
import VirtualCore

struct VirtualMachineButtonStyle: ButtonStyle {

    let vm: VBVirtualMachine

    func makeBody(configuration: Configuration) -> some View {
        LibraryItemView(
            vm: vm,
            name: vm.name,
            isPressed: configuration.isPressed
        )
    }

}

struct LibraryItemView: View {

    @State var vm: VBVirtualMachine
    @State var name: String
    var isPressed = false

    @State private var thumbnail: Image?

    var nameFieldFocus = BoolSubject()

    #if ENABLE_HARDWARE_ID_CHANGE
    @State private var isShowingDuplicateSheet = false
    #endif

    var body: some View {
        VStack(spacing: 12) {
            thumbnailView
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 4)

            EphemeralTextField($name, alignment: .leading, setFocus: nameFieldFocus) { name in
                Text(name)
            } editableContent: { name in
                TextField("VM Name", text: name)
            } validate: { name in
                do {
                    try VMLibraryController.shared.validateNewName(name, for: vm)
                    return true
                } catch {
                    return false
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
        }
        .padding([.leading, .trailing, .top], 8)
        .padding(.bottom, 12)
        .background(Material.thin, in: backgroundShape)
        .clipShape(backgroundShape)
        .background {
            if let image = vm.thumbnailImage() {
                Image(nsImage: image)
                    .resizable()
                    .blur(radius: 22)
                    .opacity(isPressed ? 0.1 : 0.4)
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 12)
        .shadow(color: Color.black.opacity(0.56), radius: 1)
        .scaleEffect(isPressed ? 0.96 : 1)
        .onAppear { refreshThumbnail() }
        .onReceive(vm.didInvalidateThumbnail) { refreshThumbnail() }
        .contextMenu { contextMenuItems }
        .onChange(of: name) { [name] newName in
            guard newName != name else { return }

            do {
                try VMLibraryController.shared.rename(vm, to: newName)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        .onChange(of: vm.name) { [vm] updatedName in
            guard updatedName != vm.name else { return }
            self.name = updatedName
        }
        #if ENABLE_HARDWARE_ID_CHANGE
        .sheet(isPresented: $isShowingDuplicateSheet) {
            DuplicateVMSheet(vm: vm)
        }
        #endif
    }

    private func refreshThumbnail() {
        if let nsImage = vm.thumbnailImage() {
            thumbnail = Image(nsImage: nsImage)
        }
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnail {
            image
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

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            NSWorkspace.shared.selectFile(vm.bundleURL.path, inFileViewerRootedAtPath: vm.bundleURL.deletingLastPathComponent().path)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            duplicate()
        } label: {
            Text("Duplicate")
        }

        Button {
            nameFieldFocus.send(true)
        } label: {
            Text("Rename")
        }

        Divider()

        Button {
            Task {
                do {
                    try await VMLibraryController.shared.moveToTrash(vm)
                } catch {
                    await NSAlert(error: error).runModal()
                }
            }
        } label: {
            Text("Move to Trash")
        }
    }

    private func duplicate() {
        #if ENABLE_HARDWARE_ID_CHANGE
        isShowingDuplicateSheet = true
        #else
        Task {
            do {
                try await VMLibraryController.shared.duplicate(vm)
            } catch {
                await NSAlert(error: error).runModal()
            }
        }
        #endif
    }

}
