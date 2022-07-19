//
//  SharedFolderListItem.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct SharedFolderListItem: View {
    @Binding var folder: VBSharedFolder

    var body: some View {
        HStack(spacing: 2) {
            Toggle(folder.shortName, isOn: $folder.isEnabled)
            label
        }
            .lineLimit(1)
            .truncationMode(.middle)
            .controlSize(.mini)
            .disabled(folder.errorMessage != nil)
            .labelsHidden()
            .padding(.vertical, 4)
            /// Easier to hit trailing edge buttons without hovering floating scroll bar.
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 4) {
            folder.icon(maxHeight: 14)

            Text(folder.shortName)
                .help(folder.url.path)

            Spacer()

            if let errorMessage = folder.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help(errorMessage)
            } else {
                Button {
                    folder.isReadOnly.toggle()
                } label: {
                    Image(systemName: folder.isReadOnly ? "pencil.slash" : "pencil")
                }
                .help(folder.isReadOnly ? "Make writable" : "Make read only")
                .buttonStyle(.plain)
                .disabled(!folder.isEnabled)
            }
        }
        .padding(.leading, 6)
        .opacity(folder.isEnabled ? 1 : 0.8)
        .opacity(folder.errorMessage != nil ? 0.3 : 1)
        .font(.system(size: 11))
    }
}

extension VBSharedFolder {
    func icon(maxHeight: CGFloat) -> some View {
        let image: NSImage
        if let externalVolumeURL {
            image = NSWorkspace.shared.icon(forFile: externalVolumeURL.path)
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        let dimension = min(image.size.width, image.size.height)
        let scale = (maxHeight) / dimension
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: maxHeight)
    }
}
