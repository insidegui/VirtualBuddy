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
            isPressed: configuration.isPressed,
            label: { configuration.label }
        )
    }

}

struct LibraryItemView<Label>: View where Label: View {

    var vm: VBVirtualMachine
    var isPressed = false
    var label: () -> Label

    @State private var thumbnail: Image?

    var body: some View {
        VStack(spacing: 12) {
            thumbnailView
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 4)

            label()
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

}
