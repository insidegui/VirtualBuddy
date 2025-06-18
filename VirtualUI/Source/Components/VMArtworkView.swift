import SwiftUI
import VirtualCore

public struct VMArtworkView: View {
    public var virtualMachine: VBVirtualMachine
    public var showsIcon: Bool
    public var iconSize: CGFloat

    public init(virtualMachine: VBVirtualMachine, showsIcon: Bool = true, iconSize: CGFloat = 44) {
        self.virtualMachine = virtualMachine
        self.showsIcon = showsIcon
        self.iconSize = iconSize
        self._content = .init(initialValue: virtualMachine.artworkContent)
    }

    enum Content {
        case image(Image)
        case blurHash(BlurHashToken)
    }

    @State private var content: Content

    public var body: some View {
        ZStack {
            switch content {
            case .image(let image): image.resizable()
            case .blurHash(let token): BlurHashFullBleedBackground(token)
            }

            if showsIcon, case .blurHash = content {
                virtualMachine.configuration.systemType.icon
                    .resizable()
                    .foregroundStyle(.white)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: virtualMachine.metadata) {
            withTransaction(\.disablesAnimations, true) {
                content = virtualMachine.artworkContent
            }
        }
    }
}

private extension VBVirtualMachine {
    var artworkContent: VMArtworkView.Content {
        if let thumbnail {
            .image(Image(nsImage: thumbnail))
        } else {
            .blurHash(metadata.backgroundHash)
        }
    }
}

#if DEBUG
private struct PreviewWrapper: View {
    var virtualMachine: VBVirtualMachine

    var body: some View {
        VMArtworkView(virtualMachine: virtualMachine)
            .aspectRatio(contentMode: .fill)
            .frame(width: 480, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(32)
    }
}


#Preview("Mac - Thumbnail") {
    PreviewWrapper(virtualMachine: .preview)
}

#Preview("Mac - Blur Hash") {
    PreviewWrapper(virtualMachine: .previewBlurHash)
}

#Preview("Mac - None") {
    PreviewWrapper(virtualMachine: .previewNoArtwork)
}

#Preview("Linux - Thumbnail") {
    PreviewWrapper(virtualMachine: .previewLinux)
}

#Preview("Linux - Blur Hash") {
    PreviewWrapper(virtualMachine: .previewLinuxBlurHash)
}

#Preview("Linux - None") {
    PreviewWrapper(virtualMachine: .previewLinuxNoArtwork)
}
#endif
